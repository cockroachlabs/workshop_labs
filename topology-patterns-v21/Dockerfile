FROM cockroachdb/cockroach:latest
RUN echo -e "[BaseOS] \nname=CentOS-\$releasever - Base \nmirrorlist=http://mirrorlist.centos.org/?release=\$releasever&arch=\$basearch&repo=BaseOS&infra=\$infra\ngpgcheck=0\nenabled=1\n" > /etc/yum.repos.d/Centos8-Repo.repo
RUN microdnf install -y iproute-tc && rm -rf /var/cache/yum