CC = gcc
CFLAGS = -Wall -Wextra -I. -I./bluez_inc/binc -O2 -g $(shell pkg-config --cflags glib-2.0 gio-2.0 bluez)
LDFLAGS = $(shell pkg-config --libs glib-2.0 gio-2.0 bluez) -L./bluez_inc/build/binc -lBinc -lm 

SRCS = main.c wifi-manager.c util.c
OBJS = $(SRCS:.c=.o)
TARGET = hubv3-btgatt-server

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)

