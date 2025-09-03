ARG VERSION=v6.5.1

FROM ghcr.io/invoke-ai/invokeai:${VERSION}-cuda

WORKDIR /invokeai

COPY ./start.sh .
COPY ./invokeai.yaml .

RUN chmod +x ./start.sh

ENTRYPOINT ["./start.sh"]
