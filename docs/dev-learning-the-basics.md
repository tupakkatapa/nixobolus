# Learning the basics

I had limited or no information about the topics of this project. This is my documentation how I've started to get familiar with these things. So far, the project has been ongoing for 6 weeks. ~ Jesse K.

It all started here: https://github.com/jhvst/nix-config

## PXE & Kexec

I started with the essentials for running NixOS completely in RAM. These were relatively easy to learn, especially with the help of a Pfsense+ router that can serve as PXE boot server provided for me by Juuso.

The only snag I hit was building the undionly.kpxe file, but I eventually figured it out and even wrote a simple shell script for learning and reproducibility purposes. You can find it on my Github page.

Here are some of the resources that helped me get started with PXE netbooting:

- https://ipxe.org/howto/chainloading
- https://forum.netgate.com/topic/111547/pfsense-as-pxe-boot-server

I was blown away when I heard about kexec, a way for booting into another kernel from the currently running one. It wasn't hard to learn, it was just awesome.

- https://wiki.archlinux.org/title/Kexec

## NixOS

When I heard about NixOS and its ability to personalize and reproduce the entire operating system within just a couple of configuration files, I was fascinated and eager to learn about Nix. I started by watching tutorials on YouTube and reading the documentation.

- https://nixos.wiki
- https://youtu.be/AGVXJ-TIv3Y

After gaining a basic understanding, I started exploring configurations made by others to see what the end result could look like. However, I found them confusing due to the scattered nature of the config files and the use of flakes, which I still haven't looked fully into. I guess it's just better to start fresh and add on as I go, rather than trying to make sense of these advanced setups.

- https://github.com/MatthiasBenaets/nixos-config
- https://github.com/Misterio77/nix-config

At the time of writing this, I have a basic understanding of the structure of NixOS configurations and how to get an OS running with home-manager and my favorite programs. There is also a very good resource for introduction to Nix which was launched recently, it is called Zero to Nix.

- https://zero-to-nix.com 

Learning NixOS is challenging, with its many pitfalls and obstacles, but I'm still motivated to continue. I'm eager to learn how to create reproducible, easy to distribute, and "unbreakable" system configurations.

## Ethereum

Before I started learning about Ethereum, I had very limited knowledge about it and how it actually works. I feel like learning Ethereum after "The Merge", the terminology is just a confusing soup of words like consensus, execution, validator, beacon, client, node, eth 2.0 and eth 1.0. The more I tried to learn, the more confused I got. But, I persevered and slowly started to grasp these concepts. Here are some of the resources that were most helpful to me as a beginner:

- https://ethereum.org/en/learn/
- https://docs.prylabs.network/docs/concepts/nodes-networks

Now, I'm focused on learning how to run and configure various nodes, and translating the configurations into templates for Nix. It's a deep dive for someone who's just interested in decentralized currency, but I'm enjoying the journey.