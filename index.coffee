AWS               = require 'aws-sdk'
{Subnetv4,IPv4}   = require 'node-cidr'
program           = require 'commander'
async             = require 'async'

validateCidr = (cidr) ->
  cidrBlock = new Subnetv4(cidr)
  unless cidrBlock._bitMask > 0
    console.log 'Error. You passed an invalid CIDR'
    process.exit 1
  return cidr
    
program.version('1.0.0')
  .option('-f, --forward_zone_id <id>', 'ID of the Route53 Hosted zone for forward lookup records')
  .option('-c, --cidr <cidr>', 'CIDR to build zones for. Example, "10.110.1.0/24"', validateCidr)
  .option('-a, --action [action]', 'Action to perform [UPSERT]', 'UPSERT')
  .option('-v, --verbose', 'enable verbose logging')
  .parse process.argv

[
  'cidr'
  'forward_zone_id'
].map (opt) ->
  unless program[opt]
    console.log "Please supply a #{opt}. See --help for usage"
    process.exit()

log = (err, message) ->
  if err
    console.log JSON.stringify err, null, 2
    process.exit 1
  if message && program.verbose
    console.log JSON.stringify message, null, 2


route53 = new AWS.Route53()

IPv4::asHostname = ->
  return 'ip-' + this.asString.replace(/\./g, '-')

cidr = new Subnetv4(program.cidr)

reverse_zone = cidr.ipList[0].reverse.split('.').slice(1, 6).join('.')

async.waterfall [
  
  # Build batch request for forward zone
  (cb) ->
    route53.getHostedZone Id: program.forward_zone_id, (err, forwardZone) ->
      log err
      
      forwardLookupChanges = 
        HostedZoneId: program.forward_zone_id
        ChangeBatch:
          Comment: "Forward lookup records for #{program.cidr} in HostedZone #{program.forward_zone_id}"
          Changes: []
            
      for address in cidr.ipList
        forwardLookupChanges.ChangeBatch.Changes.push 
          Action: program.action
          ResourceRecordSet:
            Name: address.asHostname() + '.' + forwardZone.HostedZone.Name
            TTL: 900
            Type: "A"
            ResourceRecords: [
                Value: address.asString
              ]

      cb err, forwardZone.HostedZone.Name, forwardLookupChanges
  
  # Submit batch request for forward zone
  (forwardZoneName, forwardLookupChanges, cb) ->
    route53.changeResourceRecordSets forwardLookupChanges, (err, data) ->
      cb err, forwardZoneName, data?.ChangeInfo?.Id
  
  # Find or create zone for reverse dns
  (forwardZoneName, forwardZonePollId, cb) ->
    route53.listHostedZonesByName DNSName: reverse_zone, (err, data) ->
      log err, data
      
      for zone in data.HostedZones
        if zone.Name == reverse_zone + '.'
          return cb null, forwardZoneName, forwardZonePollId, zone.Id.replace('/hostedzone/','')
      
      route53.createHostedZone { 
        CallerReference: (new Date()).toString(), 
        Name: reverse_zone 
        HostedZoneConfig: 
          Comment: "Reverse lookup records for #{program.cidr}in #{forwardZoneName}"
        }, (err, data) ->
        log err, data
        return cb err, forwardZoneName, forwardZonePollId, data.HostedZone.Id.replace('/hostedzone/','')
  
  # Build batch request for reverse zone
  (forwardZoneName, forwardZonePollId, reverseZoneid, cb) ->
    route53.getHostedZone Id: reverseZoneid, (err, data) ->
      log err
      reverseLookupChanges = 
        HostedZoneId: reverseZoneid
        ChangeBatch:
          Comment: "Reverse lookup records for #{program.cidr} in HostedZone #{reverseZoneid}"
          Changes: []
            
      for address in cidr.ipList
        reverseLookupChanges.ChangeBatch.Changes.push 
          Action: program.action
          ResourceRecordSet:
            Name: address.reverse
            TTL: 900
            Type: "PTR"
            ResourceRecords: [
                Value: address.asHostname() + '.' + forwardZoneName
              ]
              
      cb err, reverseLookupChanges, forwardZonePollId, reverseZoneid
  
  # Submit batch request for reverse zone
  (reverseLookupChanges, forwardZonePollId, reverseZoneid, cb) ->
    route53.changeResourceRecordSets reverseLookupChanges, (err, data) ->  
      cb err, forwardZonePollId, data?.ChangeInfo?.Id, reverseZoneid
      
], (err, forwardZonePollId, reverseZonePollId, reverseZoneid) ->
  log err
  
  async.series [
    
    (cb) ->
      reverseLookupChangesPoll = setInterval (->  
        route53.getChange Id: forwardZonePollId, (err, data) ->
          log err, data
          if data?.ChangeInfo?.Status == 'INSYNC'
            clearInterval reverseLookupChangesPoll
            cb null, 'forward INSYNC', reverseZoneid
      ), 15000
      
    (cb) ->    
      reverseLookupChangesPoll = setInterval (->  
        route53.getChange Id: reverseZonePollId, (err, data) ->
          log err, data
          if data?.ChangeInfo?.Status == 'INSYNC'
            clearInterval reverseLookupChangesPoll
            cb null, 'reverse INSYNC', reverseZoneid
      ), 15000
      
  ], (err, results, reverseZoneid) ->
    log err, results
    console.log JSON.stringify success: true
    
    if program.action == 'DELETE'
      route53.deleteHostedZone Id:reverseZoneid, log
