# Virtual Machine — Sample Output

## AWS (EC2 — Amazon Linux 2023)

```
$ bash scripts/examples/virtual-machine/aws.sh

==> Looking up EC2 instance public IP
     18.132.41.144
==> Connecting to ec2-user@18.132.41.144
==> Root directory listing
total 32
dr-xr-xr-x.  18 root root   237 Jun 11 01:50 .
dr-xr-xr-x.  18 root root   237 Jun 11 01:50 ..
lrwxrwxrwx.   1 root root     7 Jan 30  2023 bin -> usr/bin
dr-xr-xr-x.   5 root root 16384 Jun 11 01:50 boot
drwxr-xr-x.  14 root root  3100 Jun 18 15:11 dev
drwxr-xr-x.  77 root root 16384 Jun 18 15:11 etc
drwxr-xr-x.   3 root root    22 Jun 15 20:06 home
lrwxrwxrwx.   1 root root     7 Jan 30  2023 lib -> usr/lib
lrwxrwxrwx.   1 root root     9 Jan 30  2023 lib64 -> usr/lib64
drwxr-xr-x.   2 root root     6 Jun 11 01:49 local
drwxr-xr-x.   2 root root     6 Jan 30  2023 media
drwxr-xr-x.   3 root root    17 Jun 18 15:11 mnt
drwxr-xr-x.   6 root root    60 Jun 18 15:11 opt
dr-xr-xr-x. 160 root root     0 Jun 18 15:11 proc
dr-xr-x---.   3 root root   103 Jun 11 01:50 root
drwxr-xr-x.  30 root root   860 Jun 18 15:11 run
lrwxrwxrwx.   1 root root     8 Jan 30  2023 sbin -> usr/sbin
drwxr-xr-x.   2 root root     6 Jan 30  2023 srv
dr-xr-xr-x.  13 root root     0 Jun 18 15:11 sys
drwxrwxrwt.  11 root root   220 Jun 18 16:31 tmp
drwxr-xr-x.  12 root root   144 Jun 11 01:50 usr
drwxr-xr-x.  18 root root   251 Jun 18 15:11 var
==> Hostname
ip-10-0-1-62.eu-west-2.compute.internal
==> OS release
PRETTY_NAME="Amazon Linux 2023.12.20260611"
==> Done
```

## GCP (Compute Engine — Debian 12)

```
$ bash scripts/examples/virtual-machine/gcp.sh

==> Looking up Compute Engine instance public IP
     34.39.121.78
==> Connecting to debian@34.39.121.78
==> Root directory listing
total 68
drwxr-xr-x  18 root root  4096 Jun 18 15:01 .
drwxr-xr-x  18 root root  4096 Jun 18 15:01 ..
lrwxrwxrwx   1 root root     7 Jun  9 15:05 bin -> usr/bin
drwxr-xr-x   4 root root  4096 Jun  9 15:08 boot
drwxr-xr-x  14 root root  3060 Jun 18 15:01 dev
drwxr-xr-x  76 root root  4096 Jun 18 15:02 etc
drwxr-xr-x   3 root root  4096 Jun 18 15:02 home
lrwxrwxrwx   1 root root     7 Jun  9 15:05 lib -> usr/lib
lrwxrwxrwx   1 root root     9 Jun  9 15:05 lib64 -> usr/lib64
drwx------   2 root root 16384 Jun  9 15:04 lost+found
drwxr-xr-x   2 root root  4096 Jun  9 15:05 media
drwxr-xr-x   2 root root  4096 Jun  9 15:05 mnt
drwxr-xr-x   2 root root  4096 Jun  9 15:05 opt
dr-xr-xr-x 141 root root     0 Jun 18 15:01 proc
drwx------   3 root root  4096 Jun  9 15:07 root
drwxr-xr-x  23 root root   640 Jun 18 16:32 run
lrwxrwxrwx   1 root root     8 Jun  9 15:05 sbin -> usr/sbin
drwxr-xr-x   2 root root  4096 Jun  9 15:05 srv
dr-xr-xr-x  13 root root     0 Jun 18 15:01 sys
drwxrwxrwt  10 root root  4096 Jun 18 15:02 tmp
drwxr-xr-x  12 root root  4096 Jun  9 15:05 usr
drwxr-xr-x  12 root root  4096 Jun  9 15:06 var
==> Hostname
tf-public-cloud-vm-ac69
==> OS release
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
==> Done
```

## Azure (Linux VM — Ubuntu 22.04)

```
$ bash scripts/examples/virtual-machine/azure.sh

==> Looking up Azure VM public IP
     20.234.196.174
==> Connecting to azureuser@20.234.196.174
==> Root directory listing
total 72
drwxr-xr-x  19 root root  4096 Jun 18 15:02 .
drwxr-xr-x  19 root root  4096 Jun 18 15:02 ..
lrwxrwxrwx   1 root root     7 Jun 11 07:49 bin -> usr/bin
drwxr-xr-x   4 root root  4096 Jun 11 07:57 boot
drwxr-xr-x  17 root root  4040 Jun 18 15:02 dev
drwxr-xr-x  99 root root  4096 Jun 18 15:02 etc
drwxr-xr-x   3 root root  4096 Jun 18 15:02 home
lrwxrwxrwx   1 root root     7 Jun 11 07:49 lib -> usr/lib
lrwxrwxrwx   1 root root     9 Jun 11 07:49 lib32 -> usr/lib32
lrwxrwxrwx   1 root root     9 Jun 11 07:49 lib64 -> usr/lib64
lrwxrwxrwx   1 root root    10 Jun 11 07:49 libx32 -> usr/libx32
drwx------   2 root root 16384 Jun 11 07:53 lost+found
drwxr-xr-x   2 root root  4096 Jun 11 07:49 media
drwxr-xr-x   3 root root  4096 Jun 18 15:02 mnt
drwxr-xr-x   2 root root  4096 Jun 11 07:49 opt
dr-xr-xr-x 175 root root     0 Jun 18 13:15 proc
drwx------   4 root root  4096 Jun 18 15:02 root
drwxr-xr-x  27 root root   900 Jun 18 16:32 run
lrwxrwxrwx   1 root root     8 Jun 11 07:49 sbin -> usr/sbin
drwxr-xr-x   6 root root  4096 Jun 11 07:57 snap
drwxr-xr-x   2 root root  4096 Jun 11 07:49 srv
dr-xr-xr-x  12 root root     0 Jun 18 13:15 sys
drwxrwxrwt  11 root root  4096 Jun 18 15:08 tmp
drwxr-xr-x  14 root root  4096 Jun 11 07:49 usr
drwxr-xr-x  13 root root  4096 Jun 11 07:51 var
==> Hostname
tfpubcloudvm-3e64
==> OS release
PRETTY_NAME="Ubuntu 22.04.5 LTS"
==> Done
```
