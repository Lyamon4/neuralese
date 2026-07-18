import React from "react";
import { cn } from "../../lib/utils";

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "outline" | "ghost";
  size?: "sm" | "md" | "lg";
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = "primary", size = "md", children, ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(
          "group relative inline-flex items-center justify-center font-medium transition-all duration-300 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:pointer-events-none disabled:opacity-50 active:scale-[0.98]",
          "rounded-full tracking-wide",
          {
            "btn-glossy-primary text-white hover:scale-[1.02]": variant === "primary",
            "btn-glossy-secondary text-white hover:scale-[1.02]": variant === "secondary",

            "border border-zinc-200/80 bg-white/60 backdrop-blur-md hover:bg-white/90 text-zinc-900 shadow-[0_2px_8px_rgba(0,0,0,0.04)] hover:scale-[1.03] hover:shadow-[0_4px_16px_rgba(0,0,0,0.08)]":
              variant === "outline",
            "hover:bg-zinc-100/80 text-zinc-900 transition-colors hover:scale-[1.03]": variant === "ghost",
            
            "h-[32px] px-[14px] text-xs": size === "sm",
            "h-[38px] px-[18px] text-sm": size === "md",
            "h-[46px] px-[24px] text-base": size === "lg",
          },
          className
        )}
        {...props}
      >
        <span className="relative z-[2] flex items-center justify-center gap-2">
          {children}
        </span>
      </button>
    );
  }
);
Button.displayName = "Button";
