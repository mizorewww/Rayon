// wrangler and cf deploy import .html files as text modules.
declare module "*.html" {
  const text: string;
  export default text;
}
