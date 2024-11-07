FROM debian:bullseye-20241016-slim AS builder
RUN apt-get update && apt-get install -y bash-static

FROM busybox:1.37.0-musl
COPY --from=builder /bin/bash-static /bin/bash

CMD ["/bin/bash"]