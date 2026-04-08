.PHONY: all clean

TARGETS := serial_inject.com

all: $(TARGETS)

%.com: %.asm
	nasm -f bin -o $@ $<

clean:
	rm -f $(TARGETS)
