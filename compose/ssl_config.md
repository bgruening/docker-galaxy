#### SSL config

Using plugin for cloudns, create certbot certificate.

Make this deploy script in `/etc/letsencrypt/renewal-hooks/deploy/deploy_script.sh`:

```
#!/bin/bash

NGINX_DIR=/home/ubuntu/docker-galaxy-stable/compose/export/nginx
cp $RENEWED_LINEAGE/fullchain.pem $NGINX_DIR
cp -p $RENEWED_LINEAGE/privkey.pem $NGINX_DIR
```

This puts the SSL key and cert in `export/nginx` which gets copied to `/config` in the nginx container which in turn ends up in `/etc/nginx`.

Create dhparams.pem: `openssl dhparam -out export/nginx/dhparams.pem 4096`

Add 'docker-compose.irida\_ssl.yml` to the docker-compose command line

TODO: configure SSL for Galaxy
