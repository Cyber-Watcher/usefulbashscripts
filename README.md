The **for_minimized_ubuntu.sh** script is designed to install the necessary utilities (IMHO) to work with a minimized Ubuntu Server.

I tested this script in minimazed Ubuntu Server 22.04 and 24.04.

Since the script installs programs into your system, the user from whom you run the installation must have the appropriate rights. You can download the script yourself and edit it to suit your needs or use the following command to install it automatically:

```
curl -k https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/for_minimized_ubuntu.sh -o for_minimized_ubuntu.sh && sudo bash for_minimized_ubuntu.sh && rm for_minimized_ubuntu.sh
```

The same script for RHEL like distros.

```
curl -k https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/rhellike-afterinstall.sh -o rhellike-afterinstall.sh && sudo bash rhellike-afterinstall.sh && rm rhellike-afterinstall.sh
```

For RedOS 8

```
curl -k https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/redos8-afterinstall.sh -o redos8-afterinstall.sh && sudo bash redos8-afterinstall.sh && rm redos8-afterinstall.sh
```


The **limitb.sh** script limits memory usage for all firefox, edge, opera and chrome browser processes.

Usage example 

```
sudo ./limitb.sh 1
```

Will limit all browsers to 1GB memory.

For the script to work, you must have cgroup installed.

```
sudo apt update
sudo apt install cgroup-tools
```



