#include "image.h"
#include <stdint.h>

extern const uint8_t __fs_image_start[]; // defined by the linker

static enum ImageState image_state = IMAGE_UNCHECKED;

static const struct img1_header *header(void) {
  return (const struct img1_header *)__fs_image_start;
}

static const struct img1_entry *entry(unsigned i) {
  return (const struct img1_entry *)(__fs_image_start +
                                     header()->directory_offset +
                                     i * IMAGE_ENTRY_SIZE);
}

static void image_check(void) {
  const struct img1_header *h = header();

  // Header checks
  if (h->magic != IMAGE_MAGIC || h->version != IMAGE_VERSION ||
      h->image_size > IMAGE_MAX_SIZE || h->count > IMAGE_MAX_PROGRAMS) {
    image_state = IMAGE_INVALID;
    return;
  }

  // Directory start check
  if (h->directory_offset < IMAGE_HEADER_SIZE) {
    image_state = IMAGE_INVALID;
    return;
  }

  // Check that every entry is over 40bytes
  uint32_t dir_size = h->count * IMAGE_ENTRY_SIZE;
  uint32_t contents_start = h->directory_offset + dir_size;

  for (unsigned i = 0; i < h->count; i++) {
    const struct img1_entry *e = entry(i);
    if (e->size < IMAGE_FILE_MIN_SIZE) {
      image_state = IMAGE_INVALID;
      return;
    }
  }
  image_state = IMAGE_VALID;
}

static int is_image_valid(void) {
  if (image_state == IMAGE_UNCHECKED) {
    image_check();
  }

  return image_state;
}

int image_count() { return is_image_valid() ? header()->count : -1; }
const char *image_name(unsigned index) {
  if (image_state == IMAGE_INVALID || index > header()->count) {
    return 0;
  }
  return entry(index)->name;
}