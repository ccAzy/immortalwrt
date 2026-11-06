'use strict';
'require view';
'require uci';
'require fs';
'require ui';

/*
 * LuCI 主题切换页面
 *
 * 为什么不用原生「系统 → 系统 → 语言和界面」：那里是下拉框 + 保存并应用，
 * 两步操作且位置深。这里把已安装主题平铺成一排按钮，点一下即切换。
 *
 * 主题列表来源：uci 的 luci.themes。
 * 每个主题包自带 /etc/uci-defaults/30_luci-theme-<name>，安装后首次启动
 * 把 luci.themes.<Name>=/luci-static/<slug> 写进配置。所以**后装的主题
 * 只要自带这个脚本，就会自动出现在本页面**，无需改这里的代码。
 *
 * 切换动作：fs.exec('/usr/bin/theme-switch', [slug])。
 * 走 ubus file.exec，只需 ACL 里给该路径的 exec 权限，不依赖任何
 * 预注册的命令 —— 这点很关键，早先的实现用 luci-app-commands 的
 * theme_switch_<name> 硬编码命令，导致新装主题点按钮 404。
 */
return view.extend({
	load: function() {
		return uci.load('luci');
	},

	render: function() {
		var self = this;
		var themes = uci.get('luci', 'themes') || {};
		var current = uci.get('luci', 'main', 'mediaurlbase') || '';

		/*
		 * uci.get() 返回的是整个 section 对象，里面混着元数据：
		 *   .anonymous = false、.type = "internal"、.name = "themes"
		 * 直接 Object.keys() 会把它们当成主题渲染成一排假卡片。
		 * 过滤判据用「值是不是 /luci-static/ 开头的字符串」——
		 * 主题项形如 Argon => /luci-static/argon，元数据项的 boolean
		 * 或 "internal" 都不匹配，比只排 "." 前缀更保险。
		 */
		var names = Object.keys(themes).filter(function(k) {
			var v = themes[k];
			return k.charAt(0) !== '.' &&
			       typeof v === 'string' &&
			       v.indexOf('/luci-static/') === 0;
		}).sort();

		var cards = names.map(function(name) {
			var path = themes[name] || '';
			var slug = String(path).replace(/^\/luci-static\//, '');
			var isCurrent = (path === current);

			return E('div', {
				'style': 'border:1px solid var(--border-color, #d0d0d0);' +
					'border-radius:8px;padding:14px 18px;min-width:190px;flex:0 0 auto'
			}, [
				E('div', { 'style': 'font-size:1.1em;font-weight:600;margin-bottom:4px' }, name),
				E('div', { 'style': 'font-size:.82em;opacity:.6;margin-bottom:12px;' +
					'font-family:monospace;word-break:break-all' }, path),
				isCurrent
					? E('span', { 'class': 'label success' }, _('当前使用'))
					: E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': function() { return self.handleSwitch(name, slug); }
					}, _('切换到此主题'))
			]);
		});

		if (!names.length) {
			cards = [ E('p', {}, _('没有检测到任何已注册的主题。')) ];
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('主题切换')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('点击按钮立即切换，页面会自动刷新。若样式没变，按 Ctrl+F5 强制刷新浏览器缓存。')),
				E('div', {
					'style': 'display:flex;flex-wrap:wrap;gap:12px;margin-top:16px'
				}, cards),
				E('p', { 'style': 'margin-top:18px;opacity:.7;font-size:.9em' },
					_('主题只影响界面外观，不改动任何网络或系统配置。新装的主题只要自带注册脚本，会自动出现在这里。'))
			])
		]);
	},

	handleSwitch: function(name, slug) {
		if (!slug) {
			ui.addNotification(null, E('p', {}, _('无法解析主题路径: ') + name), 'error');
			return;
		}

		return fs.exec('/usr/bin/theme-switch', [ slug ])
			.then(function(res) {
				if (res && res.code === 0) {
					window.location.reload();
				}
				else {
					ui.addNotification(null, E('p', {},
						_('切换失败: ') + ((res && (res.stderr || res.stdout)) || '')), 'error');
				}
			})
			.catch(function(err) {
				ui.addNotification(null, E('p', {},
					_('请求失败: ') + (err && err.message ? err.message : String(err))), 'error');
			});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
