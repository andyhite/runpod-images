ARG VERSION

FROM ghcr.io/invoke-ai/invokeai:v${VERSION}-cuda

WORKDIR /

COPY --chmod=755 ./start.sh .
COPY ./invokeai.yaml ./invokeai

ENTRYPOINT ["./start.sh"]
