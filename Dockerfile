FROM dlang2/dmd-ubuntu
LABEL maintainer="Silq Team"
LABEL description="Silq is a high-level programming language for quantum computing with a strong static type system."

RUN apt update
RUN apt install -y git ldc
RUN git clone https://github.com/eth-sri/silq.git /silq
WORKDIR /silq
RUN ./dependencies-release.sh && ./build-release.sh

CMD ./silq --help
