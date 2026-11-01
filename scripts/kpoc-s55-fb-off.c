/* S55 KPOC framebuffer helper: diagnostics only, existing FBIOBLANK preserved.
 * Runs in OEM charger SELinux domain, which can write /dev/kmsg.
 * Reads LED brightness before/after FBIOBLANK; does not change brightness.
 * No autosuspend, CPU PM, battery charge, bootloader, or kernel writes.
 * Exit statuses remain: 10 framebuffer open failed, 11 FBIOBLANK failed.
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
#define N_READ 63
#define N_WRITE 64
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
#define N_READ 0
#define N_WRITE 1
#else
#error Unsupported architecture
#endif
#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define FBIOBLANK 0x4611
#ifndef FB_PATH
#define FB_PATH "/dev/graphics/fb0"
#endif
#ifndef LED_PATH
#define LED_PATH "/sys/class/leds/lcd-backlight/brightness"
#endif
static long op(const char *path,long flags){return sys3(N_OPENAT,AT_FDCWD,(long)path,flags);}
static void cl(long fd){sys3(N_CLOSE,fd,0,0);}
static void finish(long code){sys3(N_EXIT,code,0,0);for(;;){}}
static int brightness(void) {
 long fd=op(LED_PATH,O_RDONLY);
 if(fd<0)return -1;
 char b[18];
 long n=sys3(N_READ,fd,(long)b,17);
 cl(fd);
 if(n<=0)return -2;
 long value=0;
 for(long i=0;i<n;i++) {
  if(b[i]=='\n'||b[i]=='\r'||b[i]==0)break;
  if(b[i]<'0'||b[i]>'9')return -3;
  value=value*10+(b[i]-'0');
  if(value>4095)return -4;
 }
 return (int)value;
}
/* Five short log messages at most. Nonfatal on /dev/kmsg refusal. */
static void trace(const char *name,long value) {
 char b[90];int j=0;
 const char *p="<6>S55KPOC_FB ";
 while(*p && j<70)b[j++]=*p++;
 p=name;
 while(*p && j<70)b[j++]=*p++;
 b[j++]='=';
 if(value<0){b[j++]='-';value=-value;}
 char digits[20];int d=0;
 do {digits[d++]=(char)('0'+value%10);value/=10;} while(value && d<19);
 while(d>0)b[j++]=digits[--d];
 b[j++]='\n';
 long fd=op("/dev/kmsg",O_WRONLY);
 if(fd>=0){sys3(N_WRITE,fd,(long)b,j);cl(fd);}
}
void _start(void) {
 trace("LED_BEFORE",brightness());
 long fd=op(FB_PATH,O_RDWR);
 if(fd<0){trace("FBOPEN",-1);finish(10);}
 long result=sys3(N_IOCTL,fd,FBIOBLANK,4);
 cl(fd);
 trace("FBIOBLANK",result);
 trace("LED_AFTER",brightness());
 finish(result==0?0:11);
}
