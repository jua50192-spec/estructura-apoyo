# Estructura de Apoyo — guía para ponerla en marcha

Archivos de este paquete:
- `index.html` — la aplicación (no se edita).
- `config.js` — aquí se pegan los 2 datos de Supabase.
- `schema.sql` — crea las tablas y los permisos en Supabase.
- `padron_PRUEBA.pdf` — PDF con datos inventados, para probar.

Los datos de personas viven SOLO en Supabase. GitHub guarda únicamente el programa (index.html y config.js).

---

## Parte 1 — Supabase (el servidor)

1. Entre a **supabase.com** y cree una cuenta. Esa cuenta es suya; no comparta su clave con nadie.
2. **New project**. Nombre: `estructura-apoyo`. Escriba una **clave de la base de datos** y guárdela en un lugar seguro. Región: la más cercana a República Dominicana (por ejemplo, East US). Plan: Free para la prueba.
3. Espere a que termine de crearse (1 a 2 minutos).
4. Menú izquierdo → **SQL Editor** → **New query**. Abra `schema.sql`, copie TODO el texto, péguelo y toque **Run**. Debe decir «Success».
5. Menú **Authentication** → **Sign In / Providers** (o «Providers») → **Email** → apague **Confirm email** y guarde. Si no se apaga, los coordinadores nuevos no podrán entrar.
6. **Crear su usuario administrador:** Authentication → **Users** → **Add user** → **Create new user**.
   - Email: `antonio@estructura.app` (escriba el usuario que quiera, siempre terminado en `@estructura.app`)
   - Password: una clave fuerte
   - Marque **Auto Confirm User**.
7. Vuelva a **SQL Editor** → New query, pegue esto (cambie el correo si usó otro) y **Run**:

```sql
insert into perfiles (id, nombre, rol)
select id, 'Antonio Hernández', 'admin' from auth.users where email = 'antonio@estructura.app';
```

8. **Settings** → **API Keys**. Copie dos datos:
   - la **Project URL** (empieza con https:// y termina en .supabase.co)
   - la **Publishable key** (empieza con `sb_publishable_`). Es normal que esta clave sea visible; **nunca** use ni copie la «secret key».
9. Abra `config.js` con el Bloc de notas y pegue los dos datos entre las comillas. Guarde.

## Parte 2 — GitHub (para publicar la página)

1. En GitHub: **New repository**. Nombre: `estructura-apoyo`. Público. (Dentro solo estará el programa, no datos.)
2. **Add file → Upload files**: suba `index.html` y `config.js`. **Commit changes**.
3. **Settings → Pages** → Source: *Deploy from a branch* → Branch: `main` / `(root)` → **Save**.
4. En 1 o 2 minutos aparece la dirección, parecida a `https://SU-USUARIO.github.io/estructura-apoyo/`. Esa es la dirección que usarán todos.

## Parte 3 — Primera prueba (con datos inventados)

1. Abra la dirección. Entre con su usuario (`antonio`) y su clave.
2. **Ajustes**: escriba el nombre del candidato, ponga la foto y el logo del partido. **Guardar**.
3. **Coordinadores**: cree uno de prueba (nombre, usuario, clave, zona, teléfono).
4. **Padrón**: cargue `padron_PRUEBA.pdf`. Debe decir «Completo» en los dos colegios. Toque **Subir al servidor**.
5. En otro celular, entre con el coordinador de prueba. Busque «Martínez» y toque **Añadir**.
6. Vuelva al celular de administrador → **Resumen** → **Actualizar**. Debe aparecer el seguidor.
7. Cuando todo funcione: Padrón → **Borrar todo el padrón y los seguidores** (borra los datos de prueba) y cargue el real.

## Cómo se usa cada día

**Administrador (usted o el aspirante):** Resumen, Coordinadores (crear y desactivar), Padrón (cargar), Ajustes.

**Coordinador:** busca por nombre o cédula y toca **Añadir**. Solo ve a sus propios seguidores y no puede descargar el padrón. Si otra persona ya tiene a ese votante, la app lo avisa.

## Seguridad: lo que debe saber

- Para quitar el acceso a alguien: Coordinadores → **Desactivar**. Entra de inmediato en efecto.
- La app cierra la sesión sola a los 30 minutos sin uso.
- Los permisos están en la base de datos, no solo en la pantalla. Un coordinador no puede ver el padrón completo aunque intente por otro camino.
- La cédula completa se guarda en el servidor para poder buscar. En pantalla se muestra tapada.
- Si un coordinador olvida su clave: Supabase → Authentication → Users → su usuario → cambiar la clave.
- El plan Free de Supabase se pausa si pasa una semana sin uso. Para la campaña real conviene el plan de pago.
- No comparta capturas de la app con datos de personas.

## Qué falta (para una siguiente etapa)

- Funcionar sin internet.
- Convertirla en APK (se hace con la misma dirección, igual que la app de reparaciones).
- Reporte en PDF por coordinador.
