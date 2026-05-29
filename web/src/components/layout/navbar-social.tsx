"use client";

import { Button } from "@heroui/react";
import { Icon } from "@iconify/react";

/**
 * 导航栏社交链接组件
 */
export const NavbarSocial = () => {
  return (
    <Button
      isIconOnly
      aria-label="Telegram"
      as="a"
      className="text-default-600 hover:border-primary hover:text-primary"
      href="https://t.me/CubeMihomo"
      rel="noopener noreferrer"
      size="md"
      target="_blank"
      variant="light"
    >
      <Icon icon="mdi:telegram" width={23} />
    </Button>
  );
};
