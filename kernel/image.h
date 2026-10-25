#ifndef IMAGE_H
#define IMAGE_H

#include <stdint.h>
#define IMAGE_MAGIC 0x31474d49u
#define IMAGE_HEADER_SIZE 20u
#define IMAGE_ENTRY_SIZE 24u
#define IMAGE_FILE_MIN_SIZE 40u
#define IMAGE_VERSION 1
#define IMAGE_MAX_SIZE 0x00200000u
#define IMAGE_MAX_PROGRAMS 32u
#define IMAGE_NAME_SIZE 16u

enum ImageState { IMAGE_UNCHECKED = 0, IMAGE_VALID, IMAGE_INVALID };

struct img1_header {
  uint32_t magic;
  uint32_t version;
  uint32_t image_size;
  uint32_t count;
  uint32_t directory_offset;
};

struct img1_entry {
  char name[IMAGE_NAME_SIZE];
  uint32_t offset;
  uint32_t size;
};

int image_count(void);
const char *image_name(unsigned index);

#endif