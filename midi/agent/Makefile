.PHONY: all clean

TARGETS := midi_inject.com midi_mon.com

all: $(TARGETS)

%.com: %.asm
	nasm -f bin -o $@ $<

clean:
	rm -f $(TARGETS)
