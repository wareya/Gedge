#include <stdio.h>
#include <stdint.h>

uint64_t fib()
{
    uint64_t i = 1;
    uint64_t a = 0;
    uint64_t b = 1;
    
loop_head:
    uint64_t temp = a + b;
    a = b;
    b = temp;
    
    i += 1;
    
    if (i > 42)
        return b;
    goto loop_head;
}

int main()
{
    printf("%zd\n", fib());
}