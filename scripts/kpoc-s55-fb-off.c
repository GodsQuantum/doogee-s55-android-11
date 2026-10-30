/* DOOGEE S55 KPOC: independent FB powerdown, AFTER LED off.
 * Only FBIOBLANK(4). No battery, suspend, charger or PMIC IO.
 * Exit 0 success; 10 open fail; 11 ioctl fail.
 */
#if defined(__aarch64__)
static long sys3(long n,long a,long b,long c) {
 register long x0 __asm__("x0")=a,x1 __asm__("x1")=b,x2 __asm__("x2")=c,x8 __asm__("x8")=n;
 __asm__ volatile("svc 0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");return x0;
}
#define N_OPENAT 56
#define N_IOCTL 29
#define N_CLOSE 57
#define N_EXIT 93
#elif defined(__x86_64__)
static long sys3(long n,long a,long b,long c) {
 long result;register long r10 __asm__("r10")=c;
 __asm__ volatile("syscall":"=a"(result):"a"(n),"D"(a),"S"(b),"d"(r10):"rcx","r11","memory");
 return result;
}
#define N_OPENAT 257
#define N_IOCTL 16
#define N_CLOSE 3
#define N_EXIT 60
#else
#error Unsupported architecture
#endif
#define AT_FDCWD (-100)
#define O_RDWR 2
#define FBIOBLANK 0x4611
#ifndef FB_PATH
#define FB_PATH "/dev/graphics/fb0"
#endif
static void finish(long code){sys3(N_EXIT,code,0,0);for(;;){}}
void _start(void){
 long fd=sys3(N_OPENAT,AT_FDCWD,(long)FB_PATH,O_RDWR);
 if(fd<0)finish(10);
 long result=sys3(N_IOCTL,fd,FBIOBLANK,4);
 sys3(N_CLOSE,fd,0,0);
 finish(result==0?0:11);
}
