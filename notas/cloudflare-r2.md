# Cloudflare R2 — guía para Amilcar (paso 0)

Las fotos de Scanova se guardan en Cloudflare R2. Esto lo hace Amilcar con su propia cuenta;
yo lo guío pero NUNCA manejo sus contraseñas, su tarjeta ni sus claves.

1. Crear la cuenta en https://dash.cloudflare.com/sign-up (correo + contraseña). Es gratis.
2. En el menú de la izquierda, **R2 Object Storage**. La primera vez pide **poner una tarjeta**:
   es requisito de Cloudflare para prender R2, aunque los primeros 10 GB al mes son gratis y lo
   demás cuesta unos centavos por GB.
3. **Create bucket** → nombre `scanova` → ubicación automática → Create.
4. En R2 → **Manage R2 API Tokens** → **Create API Token**:
   - nombre: `scanova-app`
   - permisos: **Object Read & Write**
   - aplicar a: **solo el bucket `scanova`**
   - duración: sin caducidad
   Al crear, Cloudflare enseña UNA sola vez: **Access Key ID**, **Secret Access Key** y el
   **endpoint** (una dirección que termina en `.r2.cloudflarestorage.com`). No cerrar esa pantalla
   hasta terminar el paso 5.
5. En Supabase → proyecto de Field Reports → **Edge Functions → Secrets** → agregar 4 secretos,
   copiando y pegando él mismo (yo no los veo):
   - `R2_ACCOUNT_ID` = el número de cuenta de Cloudflare (está en la dirección del endpoint, antes de `.r2.cloudflarestorage.com`)
   - `R2_ACCESS_KEY_ID` = Access Key ID
   - `R2_SECRET_ACCESS_KEY` = Secret Access Key
   - `R2_BUCKET` = `scanova`
6. Avisarme "ya están los secretos". Con eso despliego la función `fotos-subir` y probamos con
   una foto de prueba. Nada de fotos reales hasta que el paso 2 pase.

Si en algún paso la pantalla no se parece a esto, mandarme una captura y seguimos desde ahí.
