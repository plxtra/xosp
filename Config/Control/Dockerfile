FROM mcr.microsoft.com/dotnet/runtime:8.0

COPY --from=mcr.microsoft.com/dotnet/sdk:8.0 /usr/share/powershell /usr/share/powershell
RUN ln -s /usr/share/powershell/pwsh /usr/bin/pwsh

COPY --from=${RegistryUri}${RegistryNamespace}authority-control:${ImageTag} /app /app/authority
COPY --from=${RegistryUri}${RegistryNamespace}prodigy-control:${ImageTag} /app /app/prodigy
COPY --from=${RegistryUri}${RegistryNamespace}foundry-control:${ImageTag} /app /app/foundry
COPY --from=${RegistryUri}${RegistryNamespace}oms-control:${ImageTag} /app /app/oms
COPY --from=${RegistryUri}${RegistryNamespace}sessions-control:${ImageTag} /app /app/sessions

COPY ${CertificateFile}.crt /usr/local/share/ca-certificates/xosp-root.crt
RUN update-ca-certificates

ENTRYPOINT ["/usr/bin/pwsh"]