# How to install inside a container

`docker build -t xosp:latest .`

```
docker run --rm -it -v ${pwd}/Docker:/xosp/Docker -v ${pwd}/XOSP-Params.json:/xosp/XOSP-Params.json -v ${home}/.aws:/root/.aws -v ${home}/Plxtra:/root/Plxtra -v /var/run/docker.sock:/var/run/docker.sock xosp:latest
```