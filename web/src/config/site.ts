export type SiteConfig = typeof siteConfig;

export const siteConfig = {
  name: "NB面板",
  description: "NB面板 - 隧道管理控制面板",
  navItems: [
    {
      label: "仪表盘",
      href: "/dashboard",
    },
    {
      label: "通道管理",
      href: "/tunnels",
    },
    {
      label: "端点管理",
      href: "/endpoints",
    },
  ],
  navMenuItems: [
    {
      label: "设置",
      href: "/settings",
    },
    {
      label: "退出登录",
      href: "/logout",
    },
  ],
  links: {
    github: "",
    docs: "",
  },
};
