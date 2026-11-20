# CPU-only subset of the upstream v1.7.5 build, using Apple's Accelerate framework.
UPSTREAM := build/vendor/whisper.cpp-1.7.5
OUTPUT := build/whisper-$(shell uname -m)
GG := ggml/src
CPU := $(GG)/ggml-cpu
C := $(GG)/ggml.c $(GG)/ggml-alloc.c $(GG)/ggml-quants.c $(CPU)/ggml-cpu.c $(CPU)/ggml-cpu-quants.c
CPP := $(GG)/ggml-backend.cpp $(GG)/ggml-backend-reg.cpp $(GG)/ggml-opt.cpp $(GG)/ggml-threading.cpp $(GG)/gguf.cpp \
       $(CPU)/ggml-cpu.cpp $(CPU)/ggml-cpu-traits.cpp $(CPU)/ggml-cpu-aarch64.cpp $(CPU)/ggml-cpu-hbm.cpp \
       $(CPU)/binary-ops.cpp $(CPU)/unary-ops.cpp $(CPU)/amx/amx.cpp $(CPU)/amx/mmq.cpp \
       $(GG)/ggml-blas/ggml-blas.cpp src/whisper.cpp
OBJECTS := $(addprefix $(OUTPUT)/,$(addsuffix .o,$(C) $(CPP)))
FLAGS := -O3 -DNDEBUG -mmacosx-version-min=14.0 -DGGML_USE_CPU -DGGML_USE_BLAS -DGGML_USE_ACCELERATE \
         -DGGML_BLAS_USE_ACCELERATE -DACCELERATE_NEW_LAPACK -DACCELERATE_LAPACK_ILP64 \
         $(addprefix -I$(UPSTREAM)/,include src ggml/include ggml/src $(CPU))
ifeq ($(shell uname -m),arm64)
FLAGS += -mcpu=apple-m1
endif

.PHONY: library
library: $(OUTPUT)/libwhisper.a

$(OUTPUT)/libwhisper.a: $(OBJECTS)
	xcrun ar rcs $@ $^

$(OUTPUT)/%.c.o: $(UPSTREAM)/%.c Scripts/whisper.mk
	@mkdir -p $(@D)
	xcrun clang -std=gnu11 $(FLAGS) -c $< -o $@

$(OUTPUT)/%.cpp.o: $(UPSTREAM)/%.cpp Scripts/whisper.mk
	@mkdir -p $(@D)
	xcrun clang++ -std=c++17 $(FLAGS) -c $< -o $@
