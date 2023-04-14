#!/bin/bash
# yay -S qemu-desktop libvirt virt-install

# ERROR Operation not supported: Cannot use direct socket mode if no URI is set
# uri_default = "qemu:///session" >> /etc/libvirt/libvirt.conf
#
# ERROR Failed to connect socket to '/var/run/libvirt/virtqemud-sock': No such file or directory
# systemctl restart libvirtd
# systemctl enable libvirtd
#
# ERROR Cannot get interface MTU on 'virbr0': No such device
# sudo virsh net-create /etc/libvirt/qemu/networks/default.xml

# Args
HOSTNAME="$1"

# Paths
PARENT_DIR=$( cd -- "$( dirname -- "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )" &> /dev/null && pwd )
HOST_DIR="$PARENT_DIR/result/$HOSTNAME/"
IMAGE_DIR="/var/lib/libvirt/images"
# if not default folder /var/lib/libvirt/images, do selinux fix:
# sudo semanage fcontext -a -t svirt_image_t "/mnt/data/images(/.*)?"
# sudo restorecon -vR /mnt/data/images

# Server random number
randomNumber=$((1 + $RANDOM % 9999))
#echo "Random number $randomNumber"

# Define variables
VM_NAME="test"
RAM=2048 # MB
VCPUS=2
DISK_SIZE=10 # G
INITRD_FILE=$(readlink -f "$HOST_DIR/initrd")
BZIMAGE_FILE=$(readlink -f "$HOST_DIR/bzImage")
QCOW2_FILE="$IMAGE_DIR/$VM_NAME-$randomNumber.qcow2"
KERNEL_ARGS=$(sed -n '/--command-line/p' $HOST_DIR/kexec-boot | cut -d\" -f2)

# ERROR Guest name 'foobar' is already in use.
sudo virsh destroy $VM_NAME >/dev/null 2>&1
sudo virsh undefine $VM_NAME >/dev/null 2>&1

# Create state disk
sudo qemu-img create -f qcow2 -o preallocation=metadata $QCOW2_FILE ${DISK_SIZE}G

# Create new server
sudo virt-install -n $VM_NAME --vcpus $VCPUS -r $RAM \
  --os-variant=fedora31 --import \
  --network bridge=virbr0 \
  --disk $QCOW2_FILE,format=qcow2,bus=virtio \
  --install kernel=${BZIMAGE_FILE},initrd=${INITRD_FILE},kernel_args_overwrite=yes,kernel_args="${KERNEL_ARGS}" \
  --noautoconsole