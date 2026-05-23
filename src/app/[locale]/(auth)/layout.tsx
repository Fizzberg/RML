export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <section className="container max-w-md py-12">
      <div className="rounded-md border bg-surface p-6">{children}</div>
    </section>
  );
}
