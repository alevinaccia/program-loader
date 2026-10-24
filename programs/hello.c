#include "lib/printf.h"
#include "lib/syscalls.h"

static int calls;     /* BSS: zero at start */
int start_value = 40; /* .data: copied from the file */

int main(void) {
  calls++;
  printf("hello: value=%d calls=%d\n", start_value + 2, calls);
  return 0;
}
