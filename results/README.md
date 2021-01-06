All \*_sys_activity.dat files are combo system activity information collected by [sar](http://sebastien.godard.pagesperso-orange.fr/) and can be plotted in SVG format by using sadf (included in the sysstat package, see sadf(1)). Here is an example:
```bash
sadf -g -O autoscale,showidle,showinfo,showtoc -t XXX_sys_activity.dat -- -A > output.svg
```
