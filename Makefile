# Defaults
IMAGE_NAME ?= fedora-iot-rpi4
TAG        ?= localhost/$(IMAGE_NAME):latest
ARCH       ?= aarch64
CONTAINERFILE ?= Containerfile

# OS-specific sudo
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  SUDO ?= sudo
else
  SUDO :=
endif

# Optional build args
BUILD_ARGS :=
ifneq ($(strip $(PUBKEY)),)
  BUILD_ARGS += --build-arg PUBKEY="$(PUBKEY)"
endif
ifneq ($(strip $(SELINUX_MODE)),)
  BUILD_ARGS += --build-arg SELINUX_MODE=$(SELINUX_MODE)
endif

# Tool discovery
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
SHFMT      := $(shell command -v shfmt 2>/dev/null)

.PHONY: help build-container smoke image lint format tools clean distclean

help:
	@echo "Targets:"
	@echo "  build-container   Build aarch64 bootc container image"
	@echo "  smoke             Run a minimal container smoke test"
	@echo "  image             Build bootable .img via build.sh"
	@echo "  lint              Run shellcheck + shfmt (diff mode)"
	@echo "  format            Format shell scripts with shfmt"
	@echo "  tools             Install lint tools (dnf/brew/apt)"
	@echo "  clean             Remove build artifacts (.img, rootfs.tar)"
	@echo "  distclean         Also remove local container image"
	@echo ""
	@echo "Examples:"
	@echo "  make build-container SELINUX_MODE=enforcing"
	@echo "  make image"
	@echo "  make lint"

build-container:
	podman build --arch $(ARCH) $(BUILD_ARGS) -t $(TAG) -f $(CONTAINERFILE) .

smoke:
	podman run --rm $(TAG) /bin/true

image:
	$(SUDO) ./build.sh

lint:
	@if [ -z "$(SHELLCHECK)" ]; then \
	  echo "shellcheck not found. Install with: sudo dnf install -y ShellCheck | brew install shellcheck | sudo apt-get install -y shellcheck"; exit 1; \
	else \
	  "$(SHELLCHECK)" -S style build.sh; \
	fi
	@if [ -z "$(SHFMT)" ]; then \
	  echo "shfmt not found. Install with: sudo dnf install -y shfmt | brew install shfmt | sudo apt-get install -y shfmt"; exit 1; \
	else \
	  "$(SHFMT)" -d build.sh; \
	fi

format:
	@if [ -z "$(SHFMT)" ]; then \
	  echo "shfmt not found. Install with: sudo dnf install -y shfmt | brew install shfmt | sudo apt-get install -y shfmt"; exit 1; \
	else \
	  "$(SHFMT)" -w build.sh; \
	fi

tools:
	@if command -v dnf >/dev/null 2>&1; then \
	  echo "Installing with dnf..."; \
	  sudo dnf install -y ShellCheck shfmt; \
	elif command -v brew >/dev/null 2>&1; then \
	  echo "Installing with Homebrew..."; \
	  brew install shellcheck shfmt; \
	elif command -v apt-get >/dev/null 2>&1; then \
	  echo "Installing with apt-get..."; \
	  sudo apt-get update && sudo apt-get install -y shellcheck shfmt; \
	else \
	  echo "Please install shellcheck and shfmt manually for your OS."; exit 1; \
	fi

clean:
	rm -f fedora-iot-rpi4-bootc.img rootfs.tar

distclean: clean
	-@podman rmi $(TAG) 2>/dev/null || true

