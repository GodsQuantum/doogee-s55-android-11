/*
 * DOOGEE S55 KPOC LCD-off helper.
 * Execute only from KPOC init in existing MediaTek mtk_hal_light domain.
 * One-shot LED brightness=0. Does not touch PMIC, charge or suspend.
 * OFFLINE TEST FIRST. Run only with correct SELinux executable label.
 */
typedef unsigned long u64;
#if defined(__aarch64__)
static long syscall3(long n,long a,long b,long c){
  register long x0 __asm__("x0")=a,x1 __asm__("x1")=b,x2 __asm__("x2")=c,x8 __asm__("x8")=n;
  __asm__ volatile("svc 0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");return x0;
}
#define N_OPENAT 56
#define N_WRITE 64
#define N_READ 63
#define N_CLOSE 57
#define N_EXIT 93
#elif defined(__x86_64__)
static long syscall3(long n,long a,long b,long c){
  long out;
  __asm__ volatile("syscall":"=a"(out):"a"(n),"D"(a),"S"(b),"d"(c):"rcx","r11","memory");
  return out;
}
#define N_OPENAT 257
#define N_WRITE 1
#define N_READ 0
#define N_CLOSE 3
#define N_EXIT 60
#else
#error Unsupported architecture
#endif
#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#ifndef SYSFS_ROOT
#define SYSFS_ROOT ""
#endif
static long my_open(const char *p,long flags){return syscall3(N_OPENAT,AT_FDCWD,(long)p,flags);}
static long my_read(long fd,char *s,long n){return syscall3(N_READ,fd,(long)s,n);}
static long my_write(long fd,const char *s,long n){return syscall3(N_WRITE,fd,(long)s,n);}
static void my_close(long fd){syscall3(N_CLOSE,fd,0,0);}
static void finish(long code){syscall3(N_EXIT,code,0,0);for(;;){}}
static int led_off(void){
  const char *path=SYSFS_ROOT "/sys/class/leds/lcd-backlight/brightness";
  long fd=my_open(path,O_WRONLY);
  if(fd<0)return 10;
  long n=my_write(fd,"0\n",2);
  my_close(fd);
  if(n!=2)return 11;
  fd=my_open(path,O_RDONLY);
  if(fd<0)return 12;
  char b[16];
  n=my_read(fd,b,15);
  my_close(fd);
#ifdef TEST_LOCAL_REGULAR_FILE
  /* Regular files do not truncate as sysfs writes do; assert written
   * prefix only. Kernel sysfs brightness must read exactly zero. */
  return n>0&&b[0]=='0'?0:13;
#else
  if(n<1||n>15||b[0]!='0')return 13;
  for(int i=1;i<n;i++){if(b[i]!='\n'&&b[i]!='\r'&&b[i]!=0)return 14;}
  return 0;
#endif
}
void _start(void){finish(led_off());}
