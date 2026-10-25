#include "kernel/task.h"
#include "lib/printf.h"
#include "lib/syscalls.h"
#include <stdint.h>

#define LINE_MAX 31
#define NAME_MAX 15
static char line[LINE_MAX + 1];

static int str_equal(const char *a, const char *b) {
  while (*a != '\0' && *a == *b) {
    a++;
    b++;
  }
  return *a == *b;
}

void cmd_ls() {
  unsigned count = sys_image_count();
  for (unsigned i = 0; i < count; i++) {
    const char dst[NAME_MAX];
    sys_image_name(i, (char *)dst, NAME_MAX);
    printf("%d) %s \n", i, dst);
  }
}

void cmd_help() {
  printf("help - show commands \n");
  printf("ls - list programs \n");
  printf("run <name> - run a program \n");
}

void print_no_valid_cmd() { printf("command not found: %s \n", line); }

int read_line(void) {
  unsigned len = 0;
  for (;;) {
    int c = sys_read();
    if (c < 0) {
      task_delay(1);
      continue;
    }
    if (c == 0x7f || c == '\b') {
      if (len > 0) {
        len--;
        write_all("\b \b", 3);
      }
      continue;
    }
    if (c == '\r' || c == '\n') {
      write_all("\n", 1);
      line[len] = '\0';

      return len;
    }
    /* Backspace: terminals send DEL (0x7f) or BS (0x08). Drop the last
     * character and erase it on screen: back, space, back. */
    if (c == 0x7f || c == '\b') {
      if (len > 0) {
        len--;
        write_all("\b \b", 3);
      }
      continue;
    }
    if (len < LINE_MAX) {
      line[len] = (char)c;
      write_all(&line[len], 1);
      len++;
    }
  }
}

void shell_task(void) {
  for (;;) {
    printf("scratch> ");
    read_line();

    if (str_equal(line, (char *)"ls")) {
      cmd_ls();
    } else if (str_equal(line, (char *)"help")) {
      cmd_help();
    } else {
      print_no_valid_cmd();
    }
  }
}

extern uint32_t _shell_part_start[], _shell_stack_top[], _shell_part_end[];
extern uint32_t _shell_data_start[], _shell_data_end[];
extern const uint32_t _shell_data_load[];

void task_project_configure(void) {
  task_configure_shell("shell", shell_task, _shell_stack_top,
                       (uint32_t)_shell_part_start, (uint32_t)_shell_part_end,
                       _shell_data_start, _shell_data_end, _shell_data_load);
}