import { getTranslations } from 'next-intl/server';

interface AddressPageProps {
  params: Promise<{ id: string }>;
}

export default async function AddressPage({ params }: AddressPageProps) {
  const { id } = await params;
  const t = await getTranslations();

  return (
    <section className="container py-8">
      <h1 className="text-xl font-semibold tracking-tight">{t('address.title')}</h1>
      <p className="mt-1 font-mono text-xs text-muted-foreground">id: {id}</p>
      <p className="mt-4 text-sm text-muted-foreground">{t('common.scaffoldNotice')}</p>
    </section>
  );
}
