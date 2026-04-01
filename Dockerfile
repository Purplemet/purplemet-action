FROM ppmsupport/purplemet-cli:latest AS cli

FROM alpine:3.19

RUN apk add --no-cache ca-certificates jq && \
    addgroup -g 65532 -S nonroot && \
    adduser -u 65532 -S -G nonroot -s /sbin/nologin nonroot

COPY --from=cli /usr/local/bin/purplemet-cli /usr/local/bin/purplemet-cli

COPY entrypoint.sh /entrypoint.sh
COPY ./shared/analyze.sh /usr/local/share/purplemet/analyze.sh
RUN chmod +x /entrypoint.sh /usr/local/share/purplemet/analyze.sh

USER nonroot:nonroot

ENTRYPOINT ["/entrypoint.sh"]
