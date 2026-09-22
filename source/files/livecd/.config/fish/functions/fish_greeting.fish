function fish_greeting
    set_color brcyan
    echo "Guix Rescue/Install Live — live/live · root/live"
    set_color normal
    echo "network : nmtui          rescue : sudo rescue-chroot.sh status|mount|chroot|umount"
    echo "install : cp -r ~/Guix-configs ~/cfg && ~/cfg/tools/emergency-blue.sh init /mnt"
    echo "manual  : info guix      README : ~/Desktop/README.txt"
end
