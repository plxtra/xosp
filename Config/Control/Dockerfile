FROM mcr.microsoft.com/dotnet/runtime:6.0

COPY --from=mcr.microsoft.com/dotnet/sdk:6.0 /usr/share/powershell /usr/share/powershell
RUN ln -s /usr/share/powershell/pwsh /usr/bin/pwsh

COPY --from=${RegistryUri}${RegistryNamespace}prodigy-control:latest /app /app/prodigy
COPY --from=${RegistryUri}${RegistryNamespace}foundry-control:latest /app /app/foundry
COPY --from=${RegistryUri}${RegistryNamespace}oms-control:latest /app /app/oms
COPY --from=${RegistryUri}${RegistryNamespace}sessions-control:latest /app /app/sessions

COPY ${CertificateFile}.crt /usr/local/share/ca-certificates/xosp-root.crt
RUN update-ca-certificates

ENTRYPOINT ["/usr/bin/pwsh"]