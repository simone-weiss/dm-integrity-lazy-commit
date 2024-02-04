get_value() {
	set -- $(hexdump -v -s $1 -n $2 -e '1/1 "%u\n"' $3)
	value=0
	j=1
	local i
	for i ; do
		value=$((value+j*i))
		j=$((j*256))
	done
}		

create_dm_integrity()
{

	[ $# -gt 2 ] || set -- $1 $2 $DEV

	dd bs=4096 count=1 if=/dev/zero of="$3" 
	dmsetup create "$1" --table "0 8 integrity $3 0 - J 5 block_size:$5 journal_sectors:$4 interleave_sectors:32768 journal_watermark:80 internal_hash:hmac(sha256):$2"
	dmsetup remove "$1"
	get_value 16 8 $3
	dmsetup create "$1" --table "0 $value integrity $3 0 - J 5 block_size:$5 journal_sectors:$4 interleave_sectors:32768 journal_watermark:80 internal_hash:hmac(sha256):$2"

	value=$((value/8))
	dd bs=4096 count=$value if=/dev/zero of="/dev/mapper/$1" 
	
}

setup_dm_integrity()
{
	get_value 16 8 $3
	dmsetup create "$1" --table "0 $value integrity $3 0 - J 5 block_size:$5 journal_sectors:$4 interleave_sectors:32768 journal_watermark:80 internal_hash:hmac(sha256):$2"

}


 # Mount and umount basic
create_dm_integrity test-int 0123456789abcdef /dev/sdb1 264 512
mkfs.ext4 -F -b 4096 -m 0 -E nodiscard,lazy_itable_init=0,lazy_journal_init=0 /dev/mapper/test-int 
rm -rf /mnt/test-int/
mkdir /mnt/test-int
mount -t ext4 /dev/mapper/test-int /mnt/test-int
cp /usr/share/et/et_c.awk /mnt/test-int
umount /mnt/test-int
dmsetup remove /dev/mapper/test-int 

setup_dm_integrity test-int 0123456789abcdef /dev/sdb1 264 512
mount -t ext4 /dev/mapper/test-int /mnt/test-int
cmp -s /usr/share/et/et_c.awk /mnt/test-int/et_c.awk
if [[ $? -eq 0 ]]; then
	echo "PASS: Mount and umount basic"
else
	echo "FAIL: Mount and umount basic"
fi
umount /mnt/test-int
dmsetup remove /dev/mapper/test-int

# mount without dm-int setup
mount -t ext4 /dev/sdb1 /mnt/test-int
if [[ $? -eq 0 ]]; then
        echo "FAIL: Mounting without dm-integrity setup possible"
else
        echo "PASS: Successfully detected mount error"
fi

# manipulate data
setup_dm_integrity test-int 0123456789abcdef /dev/sdb1 264 512
rm -rf /mnt/test-int/
mkdir /mnt/test-int
mount -t ext4 /dev/mapper/test-int /mnt/test-int
echo 'Unique string' > /mnt/test-int/test && sync
umount /mnt/test-int
dmsetup remove /dev/mapper/test-int

hexdump -C /dev/sdb1 | grep "Unique string"

addresses=$(hexdump -C /dev/sdb1 | grep "Unique string" | awk '{print $1}')
for item in $addresses; do 
     echo V | /bin/dd bs=1 count=1 seek=${item}
     conv=notrunc of=/dev/sdb1
     sync
done
hexdump -C /dev/sdb1 | grep "Vnique string"
sync

setup_dm_integrity test-int 0123456789abcdef /dev/sdb1 264 512
if [[ $? -eq 0 ]]; then
        echo "FAIL: Setup possible with manipulating data"
else
        echo "PASS: Setup not possible with manipulating data"
fi

