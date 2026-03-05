.PHONY: proto install push

.DEFAULT_GOAL := proto

# Proto
PROTO_DIR  = ./proto
PROTO_OUT  = ./pkg
MODULE     = github.com/nhassl3/servicehub

# All .proto files except vendored dependencies (googleapis, validate)
PROTO_FILES = $(shell find $(PROTO_DIR) -name "*.proto" \
	-not -path "*/googleapis/*" \
	-not -path "*/validate/*")

install:
	@go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	@go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	@go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@latest
	@go install github.com/envoyproxy/protoc-gen-validate@latest

push:
	@eval "$(ssh-agent -s)"
	@ssh-add servicehub_contracts_sshkey

proto:
	@mkdir -p $(PROTO_OUT)
	@protoc \
		--proto_path=$(PROTO_DIR) \
		--proto_path=/usr/include \
		--go_out=$(PROTO_OUT) \
		--go_opt=module=$(MODULE) \
		--go-grpc_out=$(PROTO_OUT) \
		--go-grpc_opt=module=$(MODULE) \
		--grpc-gateway_out=$(PROTO_OUT) \
		--grpc-gateway_opt=module=$(MODULE) \
		--grpc-gateway_opt=generate_unbound_methods=true \
		--validate_out="lang=go:$(PROTO_OUT)" \
		--validate_opt=module=$(MODULE) \
		$(PROTO_FILES)
	@echo "Successfully built protocol buffers code files"
