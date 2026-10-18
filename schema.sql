-- مدار المبيعات: مخطط Supabase أولي
-- نفّذ من SQL Editor في مشروع Supabase. فعّل RLS ولا تستخدم service_role في المتصفح.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name text not null,
  phone text,
  address text,
  notes text,
  opening_balance numeric(14,2) not null default 0 check (opening_balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists customers_owner_idx on public.customers(owner_id);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  invoice_number text not null,
  invoice_date date not null,
  amount numeric(14,2) not null check (amount > 0),
  invoice_type text not null check (invoice_type in ('cash','credit')),
  payment_method text,
  due_term integer check (due_term in (30,45,60)),
  due_date date,
  notes text,
  is_historical boolean not null default false,
  created_at timestamptz not null default now(),
  unique(owner_id, invoice_number)
);
create index if not exists invoices_owner_date_idx on public.invoices(owner_id, invoice_date);
create index if not exists invoices_customer_idx on public.invoices(customer_id);

create table if not exists public.collections (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  invoice_id uuid references public.invoices(id) on delete restrict,
  opening_balance_customer_id uuid references public.customers(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  collection_date date not null,
  payment_method text,
  reference text,
  notes text,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  check ((invoice_id is not null)::int + (opening_balance_customer_id is not null)::int = 1)
);
create index if not exists collections_owner_date_idx on public.collections(owner_id, collection_date);

create table if not exists public.historical_sales (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  sale_date date,
  customer_name text,
  original_invoice_number text,
  amount numeric(14,2) not null default 0,
  source_file text,
  possible_duplicate boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  owner_id uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  commission_rate numeric(6,3) not null default 2 check (commission_rate >= 0 and commission_rate <= 100),
  monthly_deduction numeric(14,2) not null default 20000 check (monthly_deduction >= 0),
  due_soon_days integer not null default 7 check (due_soon_days between 0 and 90),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  action text not null,
  entity_type text not null,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.invoices enable row level security;
alter table public.collections enable row level security;
alter table public.historical_sales enable row level security;
alter table public.app_settings enable row level security;
alter table public.audit_log enable row level security;

-- كل مستخدم يرى ويعدل بياناته فقط. بيانات المستخدمين غير مشتركة افتراضيًا.
do $$ declare t text; begin
  foreach t in array array['profiles','customers','invoices','collections','historical_sales','app_settings','audit_log'] loop
    execute format('drop policy if exists "owner manages own rows" on public.%I', t);
    execute format('create policy "owner manages own rows" on public.%I for all using (auth.uid() = id or auth.uid() = owner_id) with check (auth.uid() = id or auth.uid() = owner_id)', t);
  end loop;
end $$;

-- ملاحظة: هذا مخطط ابتدائي؛ قبل الاستخدام الفعلي أضف قيودًا/دوال RPC ذرية
-- للتحقق من الرصيد قبل التحصيل، وسياسة مشاركة/أدوار حسب نموذج العمل.
