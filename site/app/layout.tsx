import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Glia — tell the model who you are",
  description:
    "An open experiment and a native macOS stack: injecting who you are makes an agent measurably sharper — as a complement to what's relevant, proven under blind judges. Built on gbrain.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
