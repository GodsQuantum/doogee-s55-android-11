/*
 * S55 KPOC UI bridge: self-contained Linux/AArch64 static executable.
 * Keeps the stock kernel/PMIC, OEM boot and fuel gauge. Never writes
 * battery/charging sysfs; LCD powerdown is delegated to Android init.
 * Show measured values ONLY; suppress fake "0%" if fuel gauge unavailable.
 * Target: MT6750/MT6755 kernel 3.18, 64-bit arm static ELF, KPOC only.
 *
 * No libc, linker, APEX, Android HAL or dynamic services.
 * Source is experimental: OFFLINE TEST FIRST, NEVER FLASH/INSTALL BLINDLY.
 */
typedef unsigned long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef long i64;

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_RDWR 2
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
#define FBIOGET_VSCREENINFO 0x4600
#define FBIOGET_FSCREENINFO 0x4602
#define FBIOBLANK 0x4611

#ifndef SYSFS_ROOT
#define SYSFS_ROOT ""
#endif
#ifndef FB_PATH
#define FB_PATH "/dev/graphics/fb0"
#endif

#if defined(__aarch64__)
static inline long call6(long n,long a,long b,long c,long d,long e,long f){
 register long x0 __asm__("x0")=a, x1 __asm__("x1")=b,
 x2 __asm__("x2")=c, x3 __asm__("x3")=d,
 x4 __asm__("x4")=e, x5 __asm__("x5")=f, x8 __asm__("x8")=n;
 __asm__ volatile("svc 0":"+r"(x0):"r"(x1),"r"(x2),"r"(x3),"r"(x4),"r"(x5),"r"(x8):"memory");
 return x0;
}
#define N_READ 63
#define N_WRITE 64
#define N_CLOSE 57
#define N_OPENAT 56
#define N_IOCTL 29
#define N_MMAP 222
#define N_MUNMAP 215
#define N_NANOSLEEP 101
#define N_EXIT 93
#elif defined(__x86_64__)
static inline long call6(long n,long a,long b,long c,long d,long e,long f){
 register long r10 __asm__("r10")=d, r8 __asm__("r8")=e, r9 __asm__("r9")=f;
 long ret;
 __asm__ volatile("syscall":"=a"(ret):"a"(n),"D"(a),"S"(b),"d"(c),"r"(r10),"r"(r8),"r"(r9):"rcx","r11","memory");
 return ret;
}
#define N_READ 0
#define N_WRITE 1
#define N_CLOSE 3
#define N_OPENAT 257
#define N_IOCTL 16
#define N_MMAP 9
#define N_MUNMAP 11
#define N_NANOSLEEP 35
#define N_EXIT 60
#else
#error Unsupported target: AArch64 production, x86_64 for offline tests only.
#endif

static long sc_open(const char *p,int flags){return call6(N_OPENAT,AT_FDCWD,(long)p,flags,0,0,0);}
static long sc_read(int fd,void *p,u64 n){return call6(N_READ,fd,(long)p,n,0,0,0);}
static void sc_close(int fd){call6(N_CLOSE,fd,0,0,0,0,0);}
static long sc_write(int fd,const char *p,u64 n){return call6(N_WRITE,fd,(long)p,n,0,0,0);}
static long sc_ioctl(int fd,long op,void *buf){return call6(N_IOCTL,fd,op,(long)buf,0,0,0);}
static void *sc_mmap(int fd,u64 len){return (void *)call6(N_MMAP,0,len,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);}
static void sc_unmap(void *p,u64 n){call6(N_MUNMAP,(long)p,n,0,0,0,0);}
static void pause_ms(u64 ms){i64 tm[2]={(i64)(ms/1000),(i64)((ms%1000)*1000000)};call6(N_NANOSLEEP,(long)tm,0,0,0,0,0);}
static void terminate(int code){call6(N_EXIT,code,0,0,0,0,0);for(;;){}}
static u64 slen(const char *s){u64 i=0;while(s[i]&&i<1024)i++;return i;}
static void logmsg(const char *s){
 long fd=sc_open("/dev/kmsg",O_RDWR);
 if(fd>=0){sc_write((int)fd,s,slen(s));sc_close((int)fd);}
#if defined(TEST_ONE_SHOT) || defined(TEST_TIMED_ONESHOT)
 sc_write(1,s,slen(s));
#endif
}
static int starts(const char *a,const char *b){
 while(*b){if(*a++!=*b++)return 0;}return 1;
}
static int read_string(const char *p,char *out,int max){
 if(max<2)return -1;
 long fd=sc_open(p,O_RDONLY);
 if(fd<0)return -1;
 long n=sc_read((int)fd,out,(u64)(max-1));
 sc_close((int)fd);
 if(n<=0||n>=max)return -1;
 out[n]=0;return (int)n;
}
static int to_int(const char *p){
 int sign=1,at=0,number=0,digits=0;
 while(p[at]==' '||p[at]=='\t')at++;
 if(p[at]=='-'){sign=-1;at++;}
 for(;p[at]>='0'&&p[at]<='9'&&digits<10;at++,digits++){
  if(number>200000000)return -1;
  number=number*10+(p[at]-'0');
 }
 if(!digits)return -1;
 return sign*number;
}
static int get_num(const char *path){
 char b[80];if(read_string(path,b,sizeof(b))<0)return -1;return to_int(b);
}
/* 50% was a fabricated KPOC fallback on this device while Android read 30%.
 * Keep raw SOC for diagnostics but do not display an unvalidated KPOC gauge.
 * Remove this guard only after native KPOC gauge initialization is measured. */
#define KPOC_SOC_CERTIFIED 0
struct State{int usb,ac,vchr,voltage,soc,valid,charging,present,connected;};
static struct State get_state(void){
 struct State s;
 char st[64];int have_status;
 s.usb=get_num(SYSFS_ROOT "/sys/class/power_supply/usb/online");
 s.ac=get_num(SYSFS_ROOT "/sys/class/power_supply/ac/online");
 s.vchr=get_num(SYSFS_ROOT "/sys/devices/platform/battery/ADC_Charger_Voltage");
 s.voltage=get_num(SYSFS_ROOT "/sys/class/power_supply/battery/batt_vol");
 s.soc=get_num(SYSFS_ROOT "/sys/class/power_supply/battery/capacity");
 s.present=get_num(SYSFS_ROOT "/sys/class/power_supply/battery/present");
 have_status=read_string(SYSFS_ROOT "/sys/class/power_supply/battery/status",st,sizeof(st));
 s.charging=have_status>=0&&(starts(st,"Charging")||starts(st,"Full"));
 /* Voltage in microvolts, VCHR in millivolts. Recognize power from the
  * actual MTK ADC even if legacy usb/online is missing in charger mode. */
 s.connected=(s.usb==1||s.ac==1||(s.vchr>=4200&&s.vchr<6000));
 /* Never display a synthetic "0%" when the gauge has not initialized. */
 s.valid=s.present==1&&s.soc>=0&&s.soc<=100 &&
         s.voltage>=3000000&&s.voltage<=4450000&&
         !(s.soc==0&&s.voltage>=3700000);
 return s;
}

/* Linux fb_var_screeninfo / fb_fix_screeninfo layouts on Linux arm64. */
struct Bitfield{u32 offset,length,msb_right;};
struct FBVar{
 u32 xres,yres,xres_virtual,yres_virtual,xoffset,yoffset,bpp,grayscale;
 struct Bitfield red,green,blue,transp;
 u32 nonstd,activate,height,width,accel_flags,pixclock;
 u32 left_margin,right_margin,upper_margin,lower_margin,hsync_len,vsync_len,sync,vmode,rotate,colorspace;
 u32 reserved[4];
};
struct FBFix{
 char id[16];u64 smem_start;u32 smem_len,type,type_aux,visual;u16 xpanstep,ypanstep,ywrapstep,pad;
 u32 line_length;u64 mmio_start;u32 mmio_len,accel;u16 capabilities,reserved[2];
};
static struct FBVar fv;
static struct FBFix ff;
static u8 *fb;
static u64 fblen;
static u32 pack(u8 r,u8 g,u8 b){
 u32 out=0;
 if(fv.red.length>0&&fv.red.length<=8)out|=((u32)(r>>(8-fv.red.length)))<<fv.red.offset;
 if(fv.green.length>0&&fv.green.length<=8)out|=((u32)(g>>(8-fv.green.length)))<<fv.green.offset;
 if(fv.blue.length>0&&fv.blue.length<=8)out|=((u32)(b>>(8-fv.blue.length)))<<fv.blue.offset;
 if(fv.transp.length>0&&fv.transp.length<=8)out|=((1u<<fv.transp.length)-1u)<<fv.transp.offset;
 return out;
}
static void pixel(int x,int y,u32 c){
 if(x<0||y<0||(u32)x>=fv.xres||(u32)y>=fv.yres)return;
 u64 a=((u64)(y+fv.yoffset)*ff.line_length)+((u64)(x+fv.xoffset)*(fv.bpp/8));
 if(a+fv.bpp/8>fblen)return;
 if(fv.bpp==32){fb[a]=(u8)c;fb[a+1]=(u8)(c>>8);fb[a+2]=(u8)(c>>16);fb[a+3]=(u8)(c>>24);}
 else if(fv.bpp==16){fb[a]=(u8)c;fb[a+1]=(u8)(c>>8);}
}
static void rect(int x,int y,int w,int h,u32 c){
 if(w<=0||h<=0)return;
 for(int yy=y;yy<y+h;yy++)for(int xx=x;xx<x+w;xx++)pixel(xx,yy,c);
}
static const u8 glyphs[14][7]={
 {14,17,19,21,25,17,14}, // 0
 {4,12,4,4,4,4,14},
 {14,17,1,2,4,8,31},
 {30,1,1,14,1,1,30},
 {2,6,10,18,31,2,2},
 {31,16,16,30,1,1,30},
 {14,16,16,30,17,17,14},
 {31,1,2,4,8,8,8},
 {14,17,17,14,17,17,14},
 {14,17,17,15,1,1,14},
 {0,0,0,0,0,12,12}, // dot
 {0,0,31,0,31,0,0}, // equal
 {14,17,1,2,4,0,4}, // '?'
 {17,17,17,17,17,10,4} // 'V'
};
static void glyph(int x,int y,int digit,int scale,u32 c){
 if(digit<0||digit>13)return;
 for(int yy=0;yy<7;yy++)for(int xx=0;xx<5;xx++){
  if(glyphs[digit][yy]&(1u<<(4-xx)))rect(x+xx*scale,y+yy*scale,scale,scale,c);
 }
}
static void render(struct State s){
 if(!fb)return;
 u32 background=pack(8,14,20),outline=pack(185,197,205);
 u32 fill=s.connected?pack(45,194,119):pack(198,77,77);
 u32 text=pack(238,242,245);
 int width=(int)fv.xres,height=(int)fv.yres;
 if(width>4096||height>4096)return;
 rect(0,0,width,height,background);
 int bw=width*58/100,bh=height*14/100;
 if(bw<70)bw=70;if(bh<30)bh=30;
 int x=(width-bw)/2,y=(height-bh)/2;
 rect(x,y,bw,bh,outline);
 rect(x+5,y+5,bw-10,bh-10,background);
 rect(x+bw,y+bh/4,bw/18,bh/2,outline);
 if(KPOC_SOC_CERTIFIED && s.valid){
  int inside=(bw-16)*s.soc/100;
  if(inside>0)rect(x+8,y+8,inside,bh-16,fill);
 }
 int scale=width/75;if(scale<2)scale=2;if(scale>9)scale=9;
 int line_w=4*6*scale;
 int tx=(width-line_w)/2,ty=y+bh+24;
 if(KPOC_SOC_CERTIFIED && s.valid){
  int percent=s.soc;
  glyph(tx,ty,(percent/10)%10,scale,text);
  glyph(tx+6*scale,ty,percent%10,scale,text);
 }else{
  glyph(tx+6*scale,ty,12,scale,text);
 }
 /* Independently show true battery voltage when available: e.g. 3.77 V.
  * This remains useful when MTK fuel gauge reports an invalid percentage. */
 if(s.voltage>=2800000&&s.voltage<=4600000){
  int centivolts=(s.voltage+5000)/10000;
  int vscale=scale>2?scale-1:scale;
  int vx=(width-5*6*vscale)/2,vy=ty+9*scale;
  glyph(vx,vy,centivolts/100,vscale,text);
  glyph(vx+6*vscale,vy,10,vscale,text);
  glyph(vx+12*vscale,vy,(centivolts/10)%10,vscale,text);
  glyph(vx+18*vscale,vy,centivolts%10,vscale,text);
  glyph(vx+24*vscale,vy,13,vscale,text); // volts, not an invented percentage
 }
}
static void sample_and_report(struct State s){
 char line[140];int at=0;
 const char *pre="s55-kpoc: usb=";
 for(const char *p=pre;*p&&at<100;p++)line[at++]=*p;
 int nums[8]={s.usb,s.ac,s.vchr,s.voltage,s.soc,s.valid,s.charging,s.connected};
 const char *names[8]={"", " ac=", " vchr_mv=", " bat_uv=", " soc=", " valid=", " charging=", " power="};
 for(int n=0;n<8;n++){
  if(n>0)for(const char *p=names[n];*p&&at<120;p++)line[at++]=*p;
  int v=nums[n],tmp[12],num=0;
  if(v<0){line[at++]='-';v=-v;}
  do{tmp[num++]=v%10;v/=10;}while(v&&num<10);
  while(num)line[at++]='0'+tmp[--num];
 }
 line[at++]='\n';line[at]=0;logmsg(line);
}
static void loop_main(void){
 int f=sc_open(FB_PATH,O_RDWR);
 if(f>=0){
  if(sc_ioctl(f,FBIOGET_VSCREENINFO,&fv)>=0&&sc_ioctl(f,FBIOGET_FSCREENINFO,&ff)>=0 &&
     (fv.bpp==16||fv.bpp==32)&&fv.xres>100&&fv.yres>100 &&
     ff.smem_len>0&&ff.smem_len<=64*1024*1024u&&ff.line_length>0){
   void *p=sc_mmap(f,ff.smem_len);
   if((i64)p>=0){fb=(u8 *)p;fblen=ff.smem_len;}
  }
 }
 for(int n=0;;n++){
  struct State s=get_state();
  if(n%6==0)sample_and_report(s);
  /* Charging and shutdown decisions belong to the stock kernel/PMIC. */
  if(fb && n==0){
   sc_ioctl(f,FBIOBLANK,(void *)0);
   render(s);
  }
  /* AOSP requests framebuffer powerdown, but this MTK driver may leave its
   * LCD LED illuminated. Turn off physical backlight as a separate step.
   * One animation only, never pulse an empty battery every 60 seconds. */
  if(n==6){
   if(fb)sc_ioctl(f,FBIOBLANK,(void *)4);
   logmsg("s55-kpoc: framebuffer blank requested; init will power off LCD LED on service exit\n");
  }
#ifdef TEST_ONE_SHOT
  break;
#else
  if(n>=8)break; /* oneshot exits; init.svc stopped triggers sysfs LED=0 */
#ifdef TEST_TIMED_ONESHOT
  pause_ms(1);
#else
  pause_ms(1000);
#endif
#endif
 }
 if(fb)sc_unmap(fb,fblen);
 if(f>=0)sc_close(f);
}
void _start(void){loop_main();terminate(0);}
