FROM mcr.microsoft.com/dotnet/runtime:8.0

COPY --from=mcr.microsoft.com/dotnet/sdk:8.0 /usr/share/powershell /usr/share/powershell
RUN ln -s /usr/share/powershell/pwsh /usr/bin/pwsh

COPY --from=docker:cli /usr/local/libexec /usr/local/libexec
COPY --from=docker:cli /usr/local/bin /usr/local/bin
COPY --from=amazon/aws-cli:latest /usr/local/aws-cli /usr/local/aws-cli
COPY --from=amazon/aws-cli:latest /usr/local/bin /usr/local/bin

WORKDIR /xosp
COPY . .

RUN mkdir Docker
VOLUME /xosp/Docker

ENTRYPOINT ["pwsh"]
