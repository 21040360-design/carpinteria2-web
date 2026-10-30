-- =====================================================================
--  Carpintería Artesanos del Bosque  |  Base de datos prog_web (v2)
--  Compatible con MySQL 5.7+ / MariaDB 10.2+
--
--  QUÉ CORRIGE RESPECTO A LA VERSIÓN ANTERIOR
--  PEDIDOS
--    * Una solicitud ahora puede tener VARIOS muebles (tabla solicitud_items),
--      igual que el carrito de la tienda.
--    * Se puede pedir SIN tener cuenta: la solicitud guarda nombre, teléfono
--      y correo de contacto; id_cliente es opcional.
--    * Folio visible para el cliente, estado "Cancelada", fecha de
--      actualización, y precio estimado "congelado" al momento del pedido.
--    * Cotizaciones: el total se calcula solo (no puede quedar descuadrado),
--      con estado y vigencia.
--  INICIO DE SESIÓN
--    * La contraseña se guarda SIEMPRE como hash (lo genera el backend).
--    * Bloqueo temporal tras intentos fallidos, último acceso y usuario activo.
--    * Tabla sesiones para login con token (se guarda solo el hash del token).
--
--  AVISO: este script BORRA y vuelve a crear las tablas de prog_web.
--  En la versión anterior solo había datos de catálogo y 3 usuarios de
--  prueba, que aquí se vuelven a insertar. Si ya capturaste datos reales,
--  respáldalos antes de ejecutarlo.
-- =====================================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS `prog_web`
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `prog_web`;

SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW  IF EXISTS `v_solicitudes_resumen`;
DROP TABLE IF EXISTS `seguimiento`;
DROP TABLE IF EXISTS `cotizaciones`;
DROP TABLE IF EXISTS `solicitud_items`;
DROP TABLE IF EXISTS `solicitudes`;
DROP TABLE IF EXISTS `sesiones`;
DROP TABLE IF EXISTS `productos`;
DROP TABLE IF EXISTS `categorias`;
DROP TABLE IF EXISTS `usuarios`;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- USUARIOS (inicio de sesión)
-- ---------------------------------------------------------------------
CREATE TABLE `usuarios` (
  `id_usuario`        INT NOT NULL AUTO_INCREMENT,
  `nombre_completo`   VARCHAR(150) NOT NULL,
  `correo_electronico` VARCHAR(150) NOT NULL,
  `telefono`          VARCHAR(20)  NOT NULL,
  `contrasena`        VARCHAR(255) NOT NULL COMMENT 'Solo hash (bcrypt/pbkdf2/argon2), nunca texto plano',
  `rol`               ENUM('Cliente','Cotizador','Administrador') NOT NULL DEFAULT 'Cliente',
  `activo`            TINYINT(1)   NOT NULL DEFAULT 1,
  `intentos_fallidos` INT          NOT NULL DEFAULT 0,
  `bloqueado_hasta`   DATETIME     NULL DEFAULT NULL,
  `ultimo_acceso`     DATETIME     NULL DEFAULT NULL,
  `fecha_registro`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_usuario`),
  UNIQUE KEY `uq_usuarios_correo` (`correo_electronico`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sesiones: el backend entrega un token aleatorio al navegador y aquí
-- guarda solo su hash SHA-256 (64 caracteres hex).
CREATE TABLE `sesiones` (
  `id_sesion`  BIGINT NOT NULL AUTO_INCREMENT,
  `id_usuario` INT NOT NULL,
  `token_hash` CHAR(64) CHARACTER SET ascii NOT NULL,
  `ip`         VARCHAR(45)  NULL DEFAULT NULL,
  `user_agent` VARCHAR(255) NULL DEFAULT NULL,
  `creada`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expira`     DATETIME NOT NULL,
  `revocada`   TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id_sesion`),
  UNIQUE KEY `uq_sesiones_token` (`token_hash`),
  KEY `idx_sesiones_usuario` (`id_usuario`),
  CONSTRAINT `fk_sesiones_usuario` FOREIGN KEY (`id_usuario`)
    REFERENCES `usuarios` (`id_usuario`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- CATÁLOGO
-- ---------------------------------------------------------------------
CREATE TABLE `categorias` (
  `id_categoria` INT NOT NULL AUTO_INCREMENT,
  `nombre`       VARCHAR(100) NOT NULL,
  `activa`       TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id_categoria`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `productos` (
  `id_producto`          INT NOT NULL AUTO_INCREMENT,
  `id_categoria`         INT NOT NULL,
  `nombre`               VARCHAR(150) NOT NULL,
  `descripcion`          TEXT NOT NULL,
  `imagen_url`           VARCHAR(255) NULL DEFAULT NULL,
  `maderas_recomendadas` VARCHAR(255) NOT NULL,
  `precio_base_estimado` DECIMAL(10,2) NOT NULL,
  `activo`               TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id_producto`),
  KEY `idx_productos_categoria` (`id_categoria`),
  CONSTRAINT `fk_productos_categoria` FOREIGN KEY (`id_categoria`)
    REFERENCES `categorias` (`id_categoria`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PEDIDOS
-- ---------------------------------------------------------------------
-- Encabezado del pedido / solicitud de cotización.
-- id_cliente es NULL cuando la persona pidió sin crear cuenta.
CREATE TABLE `solicitudes` (
  `id_solicitud`      INT NOT NULL AUTO_INCREMENT,
  `folio`             VARCHAR(20) NULL DEFAULT NULL COMMENT 'Ej. AB-2026-0001, lo asigna el backend',
  `id_cliente`        INT NULL DEFAULT NULL,
  `id_cotizador`      INT NULL DEFAULT NULL,
  `nombre_contacto`   VARCHAR(150) NOT NULL,
  `telefono_contacto` VARCHAR(20)  NOT NULL,
  `correo_contacto`   VARCHAR(150) NULL DEFAULT NULL,
  `notas_cliente`     TEXT NULL,
  `estado`            ENUM('Pendiente de Cotización','Cotizada','Aceptada','Rechazada','Cancelada')
                      NOT NULL DEFAULT 'Pendiente de Cotización',
  `fecha_creacion`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `fecha_actualizacion` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_solicitud`),
  UNIQUE KEY `uq_solicitudes_folio` (`folio`),
  KEY `idx_solicitudes_cliente` (`id_cliente`, `fecha_creacion`),
  KEY `idx_solicitudes_cotizador` (`id_cotizador`),
  KEY `idx_solicitudes_estado` (`estado`),
  CONSTRAINT `fk_solicitudes_cliente` FOREIGN KEY (`id_cliente`)
    REFERENCES `usuarios` (`id_usuario`) ON DELETE SET NULL,
  CONSTRAINT `fk_solicitudes_cotizador` FOREIGN KEY (`id_cotizador`)
    REFERENCES `usuarios` (`id_usuario`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Muebles de cada pedido (una solicitud puede tener varios).
CREATE TABLE `solicitud_items` (
  `id_item`           INT NOT NULL AUTO_INCREMENT,
  `id_solicitud`      INT NOT NULL,
  `id_producto`       INT NULL DEFAULT NULL COMMENT 'Opcional: producto de la tabla productos',
  `nombre_item`       VARCHAR(150) NOT NULL COMMENT 'Nombre del mueble al momento del pedido',
  `cantidad`          INT NOT NULL DEFAULT 1,
  `ancho_cm`          DECIMAL(6,2) NULL DEFAULT NULL,
  `alto_cm`           DECIMAL(6,2) NULL DEFAULT NULL,
  `profundo_cm`       DECIMAL(6,2) NULL DEFAULT NULL,
  `tipo_madera`       VARCHAR(100) NULL DEFAULT NULL,
  `acabado`           VARCHAR(100) NULL DEFAULT NULL,
  `especificaciones`  TEXT NULL,
  `archivo_referencia` VARCHAR(255) NULL DEFAULT NULL,
  `precio_estimado`   DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Precio unitario estimado al momento del pedido',
  PRIMARY KEY (`id_item`),
  KEY `idx_items_solicitud` (`id_solicitud`),
  KEY `idx_items_producto` (`id_producto`),
  CONSTRAINT `fk_items_solicitud` FOREIGN KEY (`id_solicitud`)
    REFERENCES `solicitudes` (`id_solicitud`) ON DELETE CASCADE,
  CONSTRAINT `fk_items_producto` FOREIGN KEY (`id_producto`)
    REFERENCES `productos` (`id_producto`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cotizaciones: puede haber más de una por solicitud (revisiones).
-- OJO: `total` es columna calculada; NO se incluye en los INSERT.
CREATE TABLE `cotizaciones` (
  `id_cotizacion`   INT NOT NULL AUTO_INCREMENT,
  `id_solicitud`    INT NOT NULL,
  `id_cotizador`    INT NULL DEFAULT NULL,
  `costo_materiales`      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `costo_mano_obra`       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `costo_herrajes_barniz` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `total` DECIMAL(10,2) AS (`costo_materiales` + `costo_mano_obra` + `costo_herrajes_barniz`) STORED,
  `dias_estimados_fabricacion` INT NOT NULL,
  `vigencia_hasta`  DATE NULL DEFAULT NULL,
  `estado`          ENUM('Emitida','Aceptada','Rechazada','Vencida') NOT NULL DEFAULT 'Emitida',
  `notas`           TEXT NULL,
  `fecha_emision`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_cotizacion`),
  KEY `idx_cotizaciones_solicitud` (`id_solicitud`),
  KEY `idx_cotizaciones_cotizador` (`id_cotizador`),
  CONSTRAINT `fk_cotizaciones_solicitud` FOREIGN KEY (`id_solicitud`)
    REFERENCES `solicitudes` (`id_solicitud`),
  CONSTRAINT `fk_cotizaciones_cotizador` FOREIGN KEY (`id_cotizador`)
    REFERENCES `usuarios` (`id_usuario`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seguimiento de fabricación de pedidos aceptados.
CREATE TABLE `seguimiento` (
  `id_seguimiento` INT NOT NULL AUTO_INCREMENT,
  `id_solicitud`   INT NOT NULL,
  `id_usuario`     INT NULL DEFAULT NULL COMMENT 'Quién registró el avance',
  `fase_actual`    ENUM('Medición','Corte/Ensamble','Barniz/Acabado','Listo para Entrega','Instalado') NOT NULL,
  `imagen_avance`  VARCHAR(255) NULL DEFAULT NULL,
  `notas`          TEXT NULL,
  `fecha_actualizacion` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_seguimiento`),
  KEY `idx_seguimiento_solicitud` (`id_solicitud`),
  KEY `idx_seguimiento_usuario` (`id_usuario`),
  CONSTRAINT `fk_seguimiento_solicitud` FOREIGN KEY (`id_solicitud`)
    REFERENCES `solicitudes` (`id_solicitud`),
  CONSTRAINT `fk_seguimiento_usuario` FOREIGN KEY (`id_usuario`)
    REFERENCES `usuarios` (`id_usuario`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Vista para la tabla "Solicitudes recientes" del panel admin.
CREATE VIEW `v_solicitudes_resumen` AS
SELECT
  s.id_solicitud,
  s.folio,
  s.nombre_contacto,
  s.telefono_contacto,
  s.estado,
  s.fecha_creacion,
  COUNT(i.id_item) AS num_items,
  COALESCE(SUM(i.cantidad * i.precio_estimado), 0) AS total_estimado
FROM solicitudes s
LEFT JOIN solicitud_items i ON i.id_solicitud = s.id_solicitud
GROUP BY s.id_solicitud;

-- ---------------------------------------------------------------------
-- DATOS INICIALES
-- ---------------------------------------------------------------------
INSERT INTO `categorias` (`id_categoria`,`nombre`,`activa`) VALUES
  (1,'Mobiliario a Medida',1),
  (2,'Carpintería Arquitectónica y de Obra',1),
  (3,'Exterior y Jardines',1);

INSERT INTO `productos`
  (`id_producto`,`id_categoria`,`nombre`,`descripcion`,`imagen_url`,`maderas_recomendadas`,`precio_base_estimado`,`activo`) VALUES
  (1,1,'Cabecera Tapizada','Cabecera de cama en madera maciza con panel central tapizado en lino.',NULL,'Pino, Encino',7600.00,1),
  (2,2,'Puerta Maciza de Cedro','Puerta de paso o principal en cedro macizo, con herrajes de latón.',NULL,'Cedro',12800.00,1),
  (3,2,'Clóset Vestidor','Clóset modular a medida con interiores en cedro, cajones con guías suaves.',NULL,'Cedro, Caoba',24000.00,1),
  (4,1,'Mesa de Comedor Roble','Mesa de comedor de líneas limpias, fabricada en tableros macizos.',NULL,'Roble, Encino',18500.00,1),
  (5,2,'Librero a Piso','Librero de cinco niveles con estructura visible en parota. Estantes regulables.',NULL,'Parota',9800.00,1);

-- Usuarios de ejemplo. La contraseña '!' NO es un hash válido, así que nadie
-- puede entrar con ella: hay que asignar la contraseña real desde el backend
-- (ver ejemplo al final). Así no queda ninguna contraseña conocida en este archivo.
INSERT INTO `usuarios`
  (`id_usuario`,`nombre_completo`,`correo_electronico`,`telefono`,`contrasena`,`rol`) VALUES
  (1,'Luis Admin','admin@artesanos.com','555-0000','!','Administrador'),
  (2,'Cotizador Taller','cotizador@artesanos.com','555-1111','!','Cotizador'),
  (3,'Cliente Frecuente','cliente@gmail.com','555-2222','!','Cliente');

-- =====================================================================
-- CONSULTAS DE REFERENCIA PARA EL BACKEND (en comentarios, no se ejecutan)
-- Usa siempre parámetros (?, %s), nunca concatenes texto del usuario.
-- =====================================================================
--
-- 1) ASIGNAR CONTRASEÑA (el hash lo genera el backend, p. ej. Werkzeug):
--    UPDATE usuarios SET contrasena = ? WHERE correo_electronico = ?;
--
-- 2) LOGIN
--    a) SELECT id_usuario, contrasena, rol, activo, bloqueado_hasta
--         FROM usuarios WHERE correo_electronico = ?;
--       Rechaza si no existe, activo = 0, o bloqueado_hasta > NOW().
--       Compara la contraseña contra el hash en el backend.
--    b) Si FALLA (el orden de las asignaciones importa en MySQL):
--       UPDATE usuarios
--          SET intentos_fallidos = intentos_fallidos + 1,
--              bloqueado_hasta = IF(intentos_fallidos >= 5,
--                                   DATE_ADD(NOW(), INTERVAL 15 MINUTE), bloqueado_hasta)
--        WHERE id_usuario = ?;
--    c) Si TIENE ÉXITO:
--       UPDATE usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL,
--              ultimo_acceso = NOW() WHERE id_usuario = ?;
--       INSERT INTO sesiones (id_usuario, token_hash, ip, user_agent, expira)
--       VALUES (?, SHA2(?, 256), ?, ?, DATE_ADD(NOW(), INTERVAL 8 HOUR));
--    d) VALIDAR SESIÓN EN CADA PETICIÓN:
--       SELECT u.id_usuario, u.rol FROM sesiones s
--         JOIN usuarios u ON u.id_usuario = s.id_usuario
--        WHERE s.token_hash = SHA2(?, 256) AND s.revocada = 0
--          AND s.expira > NOW() AND u.activo = 1;
--    e) LOGOUT: UPDATE sesiones SET revocada = 1 WHERE token_hash = SHA2(?, 256);
--
-- 3) CREAR UN PEDIDO (todo en UNA transacción):
--    START TRANSACTION;
--    INSERT INTO solicitudes (id_cliente, nombre_contacto, telefono_contacto,
--                             correo_contacto, notas_cliente)
--    VALUES (NULL_o_id, ?, ?, ?, ?);
--    SET @id = LAST_INSERT_ID();
--    UPDATE solicitudes SET folio = CONCAT('AB-', YEAR(NOW()), '-', LPAD(@id, 4, '0'))
--     WHERE id_solicitud = @id;
--    -- una fila por cada mueble del carrito:
--    INSERT INTO solicitud_items (id_solicitud, nombre_item, especificaciones, precio_estimado)
--    VALUES (@id, ?, ?, ?);
--    COMMIT;
--
-- 4) COTIZAR (el total se calcula solo; no lo insertes):
--    INSERT INTO cotizaciones (id_solicitud, id_cotizador, costo_materiales,
--           costo_mano_obra, costo_herrajes_barniz, dias_estimados_fabricacion, vigencia_hasta)
--    VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(CURDATE(), INTERVAL 15 DAY));
--    UPDATE solicitudes SET estado = 'Cotizada', id_cotizador = ? WHERE id_solicitud = ?;
