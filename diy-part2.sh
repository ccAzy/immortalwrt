#!/bin/bash
# TR3000 自定义包源

function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# Aurora 主题
rm -rf feeds/luci/themes/luci-theme-argon
git_sparse_clone master https://github.com/sbwml/luci-theme-argon luci-theme-argon

# 默认IP 192.168.6.1
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate
