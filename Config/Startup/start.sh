#!/bin/bash

# Install certificate
./certificate-tool add --file /run/secrets/certificate.crt --store-name Root

# Load the target .Net app with any arguments passed
exec dotnet "$@"
