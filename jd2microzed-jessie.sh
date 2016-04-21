#!/bin/sh -e
#
# Copyright (c) 2014-2016 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

u_boot_release="v2016.03"
u_boot_release_x15="v2015.07"
#bone101_git_sha="50e01966e438ddc43b9177ad4e119e5274a0130d"

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			echo "Patching: /etc/profile"
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

#	echo "" >> /etc/securetty
#	echo "#USB Gadget Serial Port" >> /etc/securetty
#	echo "ttyGS0" >> /etc/securetty
}

setup_desktop () {
	#fix Ping:
	#ping: icmp open socket: Operation not permitted
	if [ -f /bin/ping ] ; then
	    if command -v setcap > /dev/null; then
		if setcap cap_net_raw+ep /bin/ping cap_net_raw+ep /bin/ping6; then
		    echo "Setcap worked! Ping(6) is not suid!"
		else
		    echo "Setcap failed on /bin/ping, falling back to setuid" >&2
		    chmod u+s /bin/ping /bin/ping6
		fi
	    else
		echo "Setcap is not installed, falling back to setuid" >&2
		chmod u+s /bin/ping /bin/ping6
	    fi
	fi

	if [ -f /etc/init.d/connman ] ; then
		mkdir -p /etc/connman/ || true
		wfile="/etc/connman/main.conf"
		echo "[General]" > ${wfile}
		echo "PreferredTechnologies=ethernet" >> ${wfile}
		echo "SingleConnectedTechnology=false" >> ${wfile}
		echo "AllowHostnameUpdates=false" >> ${wfile}
		echo "PersistentTetheringMode=true" >> ${wfile}

		mkdir -p /var/lib/connman/ || true
		wfile="/var/lib/connman/settings"
		echo "[global]" > ${wfile}
		echo "OfflineMode=false" >> ${wfile}
		echo "" >> ${wfile}
		echo "[Wired]" >> ${wfile}
		echo "Enable=true" >> ${wfile}
		echo "Tethering=false" >> ${wfile}
		echo "" >> ${wfile}
	fi
}

cleanup_npm_cache () {
	if [ -d /root/tmp/ ] ; then
		rm -rf /root/tmp/ || true
	fi

	if [ -d /root/.npm ] ; then
		rm -rf /root/.npm || true
	fi

	if [ -f /home/${rfs_username}/.npmrc ] ; then
		rm -f /home/${rfs_username}/.npmrc || true
	fi
}

install_node_pkgs () {
	if [ -f /usr/bin/npm ] ; then
		cd /
		echo "Installing npm packages"
		echo "debug: node: [`nodejs --version`]"

		if [ -f /usr/local/bin/npm ] ; then
			npm_bin="/usr/local/bin/npm"
		else
			npm_bin="/usr/bin/npm"
		fi

		echo "debug: npm: [`${npm_bin} --version`]"

		#debug
		#echo "debug: npm config ls -l (before)"
		#echo "--------------------------------"
		#${npm_bin} config ls -l
		#echo "--------------------------------"

		#c9-core-installer...
		${npm_bin} config delete cache
		${npm_bin} config delete tmp
		${npm_bin} config delete python

		#fix npm in chroot.. (did i mention i hate npm...)
		if [ ! -d /root/.npm ] ; then
			mkdir -p /root/.npm
		fi
		${npm_bin} config set cache /root/.npm
		${npm_bin} config set group 0
		${npm_bin} config set init-module /root/.npm-init.js

		if [ ! -d /root/tmp ] ; then
			mkdir -p /root/tmp
		fi
		${npm_bin} config set tmp /root/tmp
		${npm_bin} config set user 0
		${npm_bin} config set userconfig /root/.npmrc

		${npm_bin} config set prefix /usr/local/

		#echo "debug: npm configuration"
		#echo "--------------------------------"
		#${npm_bin} config ls -l
		#echo "--------------------------------"

		sync

		if [ -f /usr/local/bin/jekyll ] ; then
			git_repo="https://github.com/beagleboard/bone101"
			git_target_dir="/var/lib/cloud9"

			if [ "x${bone101_git_sha}" = "x" ] ; then
				git_clone
			else
				git_clone_full
			fi

			if [ -f ${git_target_dir}/.git/config ] ; then
				chown -R ${rfs_username}:${rfs_username} ${git_target_dir}
				cd ${git_target_dir}/

				if [ ! "x${bone101_git_sha}" = "x" ] ; then
					git checkout ${bone101_git_sha} -b tmp-production
				fi

				echo "jekyll pre-building bone101"
				/usr/local/bin/jekyll build --destination bone101
			fi

			wfile="/lib/systemd/system/jekyll-autorun.service"
			echo "[Unit]" > ${wfile}
			echo "Description=jekyll autorun" >> ${wfile}
			echo "ConditionPathExists=|/var/lib/cloud9" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Service]" >> ${wfile}
			echo "WorkingDirectory=/var/lib/cloud9" >> ${wfile}
			echo "ExecStart=/usr/local/bin/jekyll build --destination bone101 --watch" >> ${wfile}
			echo "SyslogIdentifier=jekyll-autorun" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Install]" >> ${wfile}
			echo "WantedBy=multi-user.target" >> ${wfile}

			systemctl enable jekyll-autorun.service || true

			if [ -d /etc/apache2/ ] ; then
				#bone101 takes over port 80, so shove apache/etc to 8080:
				if [ -f /etc/apache2/ports.conf ] ; then
					sed -i -e 's:80:8080:g' /etc/apache2/ports.conf
				fi
				if [ -f /etc/apache2/sites-enabled/000-default ] ; then
					sed -i -e 's:80:8080:g' /etc/apache2/sites-enabled/000-default
				fi
				if [ -f /var/www/html/index.html ] ; then
					rm -rf /var/www/html/index.html || true
				fi
			fi
		fi
	fi
}

install_git_repos () {
	# git_repo="https://github.com/beagleboard/bb.org-overlays"
	# git_target_dir="/opt/source/bb.org-overlays"
	# git_clone
	# if [ -f ${git_target_dir}/.git/config ] ; then
	# 	cd ${git_target_dir}/
	# 	if [ ! "x${repo_rcnee_pkg_version}" = "x" ] ; then
	# 		is_kernel=$(echo ${repo_rcnee_pkg_version} | grep 4.1 || true)
	# 		if [ ! "x${is_kernel}" = "x" ] ; then
	# 			if [ -f /usr/bin/make ] ; then
	# 				make
	# 				make install
	# 				update-initramfs -u -k ${repo_rcnee_pkg_version}
	# 				make clean
	# 			fi
	# 		fi
	# 	fi
	# 	cd /
	# fi
}

install_build_pkgs () {
	cd /opt/
	cd /
}

other_source_links () {
	#rcn_https="https://rcn-ee.com/repos/git/u-boot-patches"

	#mkdir -p /opt/source/u-boot_${u_boot_release}/
	#wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-omap3_beagle-uEnv.txt-bootz-n-fixes.patch
	#wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch
	#mkdir -p /opt/source/u-boot_${u_boot_release_x15}/
	#wget --directory-prefix="/opt/source/u-boot_${u_boot_release_x15}/" ${rcn_https}/${u_boot_release_x15}/0001-beagle_x15-uEnv.txt-bootz-n-fixes.patch

	#echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt
	#echo "u-boot_${u_boot_release_x15} : /opt/source/u-boot_${u_boot_release_x15}" >> /opt/source/list.txt

	#chown -R ${rfs_username}:${rfs_username} /opt/source/
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	if [ -f /etc/ssh/sshd_config ] ; then
		#Make ssh root@beaglebone work..
		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
		#Starting with Jessie:
		sed -i -e 's:PermitRootLogin without-password:PermitRootLogin yes:g' /etc/ssh/sshd_config
	fi

	if [ -f /etc/sudoers ] ; then
		#Don't require password for sudo access
		echo "${rfs_username}  ALL=NOPASSWD: ALL" >>/etc/sudoers
	fi
}

is_this_qemu

setup_system
setup_desktop

#install_node_pkgs
if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
fi
#install_build_pkgs
#other_source_links
unsecure_root
#
