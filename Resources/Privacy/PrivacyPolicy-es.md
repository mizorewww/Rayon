# Política de privacidad de Rayon

_Última actualización: 28 de noviembre de 2026_

_Si las versiones de esta política en distintos idiomas difieren, prevalece la versión en inglés._

Rayon es un cliente SSH y de servidores. Tus servidores, identidades, claves, contraseñas, fragmentos, redirecciones de puertos, archivos y sesiones de terminal se quedan en tus dispositivos, y en tu propia cuenta de iCloud si activas la sincronización con iCloud. Nadie más puede leerlos, ni siquiera los desarrolladores de Rayon.

Los únicos datos que Rayon envía a sus desarrolladores son diagnósticos anónimos y recuentos de uso. Tú eliges cuánto en Ajustes › Acerca de › Diagnóstico y uso, y puedes desactivarlo en cualquier momento.

## 1. Qué envía cada nivel

- **Desactivado (0):** nada. Rayon no establece ninguna conexión con su servidor de telemetría.
- **Informes de fallos (1):** informes de fallos y bloqueos de MetricKit de Apple, despojados en tu dispositivo de todo mensaje y nombre. Lo que queda es el tipo de problema, los códigos numéricos de excepción y de señal, una categoría para el motivo de la terminación, un nombre de excepción del sistema de una lista fija, una duración aproximada del bloqueo y las pilas de llamadas como identificadores binarios y desplazamientos dentro de Rayon y del sistema.
- **Informes de fallos y uso (2):** el nivel 1, más un informe al día con recuentos de uso de funciones, cada uno redondeado a un intervalo (0, 1, 2–5, 6–20, 21–100, más de 100). Las funciones que se cuentan son las sesiones de terminal abiertas, los exploradores de archivos abiertos, las transferencias de archivos, el editor, los monitores, las sesiones de VNC y UU Remote, los fragmentos ejecutados y las redirecciones de puertos por tipo. El informe también cuenta los resultados de conexión (como éxito, inicio de sesión rechazado, tiempo de espera agotado, conexión rechazada, clave de host no confiable, host no encontrado) e indica qué métodos de inicio de sesión se usaron ese día (contraseña, clave, agente). Además incluye los tipos de clave de tus identidades (Ed25519, ECDSA, RSA), intervalos para el número de servidores e identidades guardados, si están activados la sincronización con iCloud, un tema de terminal personalizado y la ocultación de direcciones, y un intervalo para el número de días en que se usó Rayon en los últimos 28.
- **Diagnóstico detallado (3):** el nivel 2, más, aproximadamente un día de cada diez: intervalos para el tiempo de inicio de sesión, la familia de sistema operativo de los servidores que supervisas (Linux, macOS, BSD, otro) y las cifras de rendimiento diarias de Apple (tiempo de arranque, tiempo de bloqueo, memoria máxima, tiempo de CPU, escrituras en disco), cada una redondeada a un intervalo.

Cada informe incluye también la versión de Rayon, la versión principal y secundaria del sistema operativo, la plataforma (macOS, iOS o iPadOS), la clase de dispositivo (Mac con chip de Apple, Mac con Intel, iPhone o iPad), el idioma de la app (inglés, chino simplificado, chino tradicional, japonés, francés, español u otro), cómo se instaló Rayon (App Store, TestFlight o descarga directa) y un grupo de regiones aproximado (EEE/Reino Unido/Suiza, China continental u otro) obtenido del país de tu App Store.

Puedes ver los informes exactos en Ajustes › Acerca de › Diagnóstico y uso › Ver lo que se envía…

## 2. Lo que nunca se envía

En ningún nivel envía Rayon: nombres, direcciones, puertos ni nombres de usuario de servidores; contraseñas, frases de contraseña, claves, huellas de claves ni comentarios de claves; comandos, fragmentos, entrada o salida del terminal, ni el portapapeles; nombres, rutas ni tamaños de archivos; banners ni cadenas de versión remotos; mensajes de error; variables de entorno; identificadores de iCloud o de cuenta; identificadores de dispositivo (como IDFV, IDFA o números de serie); horas exactas, zona horaria, tamaño de pantalla, tipo de red ni nombre de la red Wi-Fi; ni tu ubicación.

## 3. Cómo se conservan los datos

- Los informes **no llevan ningún identificador** tuyo, de tu dispositivo ni de tu instalación. Cada informe lleva un número aleatorio que se usa solo para descartar un duplicado si se envía dos veces; se elimina en un plazo de tres días.
- El servidor **nunca lee ni guarda tu dirección IP** ni la cadena del navegador/User-Agent, y no conserva registros de solicitudes.
- Las fechas se guardan con precisión de día. Cada informe se suma a los totales diarios en cuanto llega y después se descarta. Los elementos de fallos y bloqueos se conservan **90 días** para su diagnóstico y después se eliminan.
- Los totales de menos de **10** informes nunca se muestran ni se exportan.
- Como nada te identifica, un informe no puede vincularse contigo después. Los datos no se usan para rastrearte, no se venden y no se comparten salvo con el encargado del tratamiento indicado a continuación.

## 4. Quién los trata

- **Cloudflare, Inc.** gestiona el servidor de telemetría (un Cloudflare Worker con su base de datos D1, ubicada en la región de Asia-Pacífico) como encargado del tratamiento de Rayon. La red de Cloudflare ve necesariamente la conexión, incluida su dirección IP, al entregarla; el servidor de Rayon no la lee.
- **GitHub, Inc.** responde a «Buscar actualizaciones…» en la app para Mac, que consulta a la API pública de GitHub la versión más reciente solo cuando eliges ese comando. GitHub ve esa solicitud conforme a su propia declaración de privacidad.
- **Apple** proporciona MetricKit, la sincronización con iCloud (tus datos en tu propia cuenta de iCloud) y el App Store, conforme a la política de privacidad de Apple.
- Los servicios a los que tú mismo conectas Rayon, como tus servidores, Cloudflare Access o UU Remote, reciben lo que les envías conforme a sus propias políticas.

## 5. Cambiar o retirar tu elección

Abre Ajustes › Acerca de › Diagnóstico y uso y mueve el regulador. El cambio surte efecto de inmediato. Bajar el nivel elimina, en este dispositivo, los informes y recuentos pendientes que el nuevo nivel no enviaría; Desactivado además detiene la entrega de MetricKit a Rayon y elimina la cola de informes. «Eliminar informes pendientes» y «Restablecer historial de actividad» en Ver lo que se envía… borran el resto. El ajuste se guarda en cada dispositivo y nunca se sincroniza.

Los informes ya enviados no pueden eliminarse a petición, porque nada en ellos identifica a quién pertenecen (artículo 11 del RGPD).

## 6. Base jurídica

- **EEE, Reino Unido y Suiza:** tu consentimiento. No se envía nada hasta que eliges «Compartir datos anónimos», y puedes retirarlo en cualquier momento.
- **China continental:** no se envía nada hasta que hayas visto el aviso y esta política. Los datos son información anonimizada conforme a la Ley de Protección de la Información Personal (artículo 4, artículo 73).
- **En otros lugares:** nuestro interés legítimo en corregir errores y mejorar Rayon, con datos que son anónimos desde su diseño. El nivel 2 es el predeterminado y el aviso del primer inicio te lo indica.

Rayon no está dirigido a niños y no recopila datos de ellos a sabiendas.

## 7. Contacto y cambios

Preguntas y solicitudes: https://github.com/mizorewww/Rayon/issues

Si lo que Rayon envía cambia en algún momento, esta política, el esquema en el código fuente y la etiqueta de privacidad del App Store cambiarán en la misma versión.
