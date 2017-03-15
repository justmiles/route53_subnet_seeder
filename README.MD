# Route53 Subnet Seeder
Seeds Route53 with basic forward and reverse records for a subnet. 

  ip-192-178-1-1.company.internal ... ip-192-178-1-255.company.internal
  
  
## Usage

```
Usage: route53_subnet_seeder [options]

Options:

  -h, --help                  output usage information
  -V, --version               output the version number
  -f, --forward_zone_id <id>  ID of the Route53 Hosted zone for forward lookup records
  -c, --cidr <cidr>           CIDR to build zones for. Example, "10.110.1.0/24"
  -a, --action [action]       Action to perform [UPSERT]
  -v, --verbose               enable verbose logging
```

## Examples

### Seed a subnet
```
route53_subnet_seeder --forward_zone_id NOTAREALID --cidr 10.110.1.0/24 --verbose
```

### Unseed, or delete, a subnet
```
route53_subnet_seeder --forward_zone_id NOTAREALID --cidr 10.110.1.0/24 --action DELETE --verbose
```
