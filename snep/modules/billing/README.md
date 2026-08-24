# Billing Module for SNEP #

Billing is the ability to rate calls from your SNEP PBX version 3+.

You can configure rates for each Trunk associate to a Telco and type of calls, like mobile, landlines, long distance or any other kind of calls.

## Installation ##

To install it you need some database changes and the source code inside of SNEP module structure.

1. Installing module
```tar xzf billing.tar.gz -C /var/www/html/snep/modules/```

2. Database configuration
```mysql -uUSER -pPASSWORD snep < install/schema.sql```
