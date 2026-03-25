// Copyright 2016 Proyectos y Sistemas de Mantenimiento SL (eProsima).
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/*!
 * @file payloadPubSubMain.cxx
 *
 * Punto de entrada principal del banco de pruebas DDS-Security.
 *
 * Uso:
 *   payload publisher [muestras] [bytes] [espera_us] [escenario]
 *   payload subscriber [escenario]
 *
 * Argumentos posicionales:
 *   muestras   Número de mensajes a enviar          (por defecto: 1000)
 *   bytes      Tamaño del payload en bytes          (por defecto: 1024)
 *   espera_us  Pausa entre envíos en microsegundos  (por defecto: 1000)
 *   escenario  Perfil de seguridad DDS-Security:
 *                none    → Sin seguridad (línea base de rendimiento)
 *                auth    → Solo autenticación PKI-DH, sin cifrado
 *                encrypt → Autenticación + cifrado total AES-GCM
 *                access  → Autenticación + cifrado + control de acceso por tópico
 *              (por defecto: "none")
 *
 * Ejemplos:
 *   # Línea base sin seguridad (publisher / subscriber en dos terminales):
 *   ./payload publisher 5000 1024 1000 none
 *   ./payload subscriber none
 *
 *   # Solo autenticación:
 *   ./payload publisher 5000 1024 1000 auth
 *   ./payload subscriber auth
 *
 *   # Cifrado total con AES-GCM:
 *   ./payload publisher 5000 1024 1000 encrypt
 *   ./payload subscriber encrypt
 *
 *   # Cifrado + control de acceso por tópico:
 *   ./payload publisher 5000 1024 1000 access
 *   ./payload subscriber access
 *
 * IMPORTANTE: Para los escenarios auth, encrypt y access el binario debe
 *   ejecutarse desde la raíz del proyecto (/app dentro del contenedor) para
 *   que las rutas relativas a security/pki/ y security/signed/ sean correctas.
 *   Genera los artefactos primero con:  bash generate_security_artifacts.sh
 */

#include "payloadPublisher.h"
#include "payloadSubscriber.h"

#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>

// -----------------------------------------------------------------------------
// print_usage
// -----------------------------------------------------------------------------
// Muestra el mensaje de uso en stderr. Se llama cuando los argumentos son
// incorrectos o incompletos.
// -----------------------------------------------------------------------------
static void print_usage(const char* program_name)
{
    std::cerr
        << "\n"
        << "Uso:\n"
        << "  " << program_name << " publisher [muestras] [bytes] [espera_us] [escenario]\n"
        << "  " << program_name << " subscriber [escenario]\n"
        << "\n"
        << "Argumentos (todos opcionales, con valores por defecto):\n"
        << "  muestras   Número de mensajes a enviar           [defecto: 1000]\n"
        << "  bytes      Tamaño del payload en bytes           [defecto: 1024]\n"
        << "  espera_us  Pausa entre envíos (microsegundos)    [defecto: 1000]\n"
        << "  escenario  Perfil de seguridad DDS-Security      [defecto: none]\n"
        << "               none    → Sin seguridad (línea base)\n"
        << "               auth    → Autenticación PKI-DH, sin cifrado\n"
        << "               encrypt → Autenticación + cifrado AES-GCM\n"
        << "               access  → Autenticación + cifrado + ctrl. de acceso\n"
        << "\n"
        << "Ejemplos:\n"
        << "  " << program_name << " publisher 5000 1024 1000 auth\n"
        << "  " << program_name << " subscriber auth\n"
        << "\n"
        << "NOTA: Para escenarios != none ejecutar desde la raíz del proyecto\n"
        << "      y haber generado los artefactos PKI previamente:\n"
        << "        bash generate_security_artifacts.sh\n"
        << "\n";
}

// -----------------------------------------------------------------------------
// is_valid_scenario
// -----------------------------------------------------------------------------
// Valida que el string pasado sea uno de los cuatro escenarios reconocidos.
// La función no lanza excepciones; devuelve false para facilitar el diagnóstico
// temprano en main() antes de crear ningún objeto DDS.
// -----------------------------------------------------------------------------
static bool is_valid_scenario(const std::string& escenario)
{
    return escenario == "none"    ||
           escenario == "auth"    ||
           escenario == "encrypt" ||
           escenario == "access";
}

// =============================================================================
// main
// =============================================================================
int main(int argc, char** argv)
{
    // ── 1. Determinar el modo de operación (publisher / subscriber) ──────────
    int mode = 0;   // 0 = inválido, 1 = publisher, 2 = subscriber

    if (argc >= 2)
    {
        if (std::strcmp(argv[1], "publisher") == 0)
        {
            mode = 1;
        }
        else if (std::strcmp(argv[1], "subscriber") == 0)
        {
            mode = 2;
        }
    }

    if (mode == 0)
    {
        std::cerr << "\n[Error] Primer argumento inválido o ausente.\n";
        print_usage(argv[0]);
        return 1;
    }

    // ── 2. Ramificar según el modo ──────────────────────────────────────────

    switch (mode)
    {
        // ====================================================================
        // MODO PUBLISHER
        //   argv[1] = "publisher"
        //   argv[2] = muestras   (opcional, defecto 1000)
        //   argv[3] = bytes      (opcional, defecto 1024)
        //   argv[4] = espera_us  (opcional, defecto 1000)
        //   argv[5] = escenario  (opcional, defecto "none")
        // ====================================================================
        case 1:
        {
            // Parseo de argumentos numéricos con validación básica
            uint32_t samples  = (argc > 2) ? std::stoul(argv[2]) : 1000u;
            uint32_t bytes    = (argc > 3) ? std::stoul(argv[3]) : 1024u;
            uint32_t sleep_us = (argc > 4) ? std::stoul(argv[4]) : 1000u;

            // Escenario de seguridad (5.º argumento posicional)
            std::string escenario = (argc > 5) ? std::string(argv[5]) : "none";

            // Validar el escenario antes de arrancar cualquier recurso DDS
            if (!is_valid_scenario(escenario))
            {
                std::cerr << "\n[Error] Escenario desconocido: '" << escenario << "'\n";
                print_usage(argv[0]);
                return 1;
            }

            // Resumen de la configuración que se va a usar
            std::cout << "\n[Publisher] Configuración del experimento:\n"
                      << "  Escenario : " << escenario << "\n"
                      << "  Muestras  : " << samples   << "\n"
                      << "  Bytes     : " << bytes      << "\n"
                      << "  Espera    : " << sleep_us   << " µs\n\n";

            // Inicializar el publicador con el escenario de seguridad
            payloadPublisher mypub;
            if (!mypub.init(escenario))
            {
                std::cerr << "[Publisher] Error fatal: no se pudo inicializar "
                          << "el participante DDS.\n"
                          << "  · Comprueba que los artefactos de seguridad existen "
                          << "(bash generate_security_artifacts.sh).\n"
                          << "  · Ejecuta el binario desde la raíz del proyecto.\n\n";
                return 1;
            }

            std::cout << "[Publisher] Listo. Esperando a que el suscriptor se conecte...\n";

            // Esperar hasta que haya al menos un suscriptor (publish devuelve
            // false si listener_.matched == 0) y enviar el primer mensaje.
            while (!mypub.publish(bytes, sleep_us))
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }

            std::cout << "[Publisher] ¡Suscriptor detectado! "
                      << "Enviando " << samples << " muestras de "
                      << bytes << " bytes...\n";

            // Ya enviamos 1 mensaje en el bucle de espera; enviamos el resto.
            for (uint32_t i = 1; i < samples; ++i)
            {
                mypub.publish(bytes, sleep_us);
            }

            std::cout << "[Publisher] Envío completado ("
                      << samples << " muestras).\n";

            // Dar tiempo a que el último paquete llegue al suscriptor antes
            // de que el destructor libere el participante DDS.
            std::this_thread::sleep_for(std::chrono::seconds(1));

            break;
        }

        // ====================================================================
        // MODO SUBSCRIBER
        //   argv[1] = "subscriber"
        //   argv[2] = escenario  (opcional, defecto "none")
        // ====================================================================
        case 2:
        {
            // Escenario de seguridad (2.º argumento posicional)
            std::string escenario = (argc > 2) ? std::string(argv[2]) : "none";

            if (!is_valid_scenario(escenario))
            {
                std::cerr << "\n[Error] Escenario desconocido: '" << escenario << "'\n";
                print_usage(argv[0]);
                return 1;
            }

            std::cout << "\n[Subscriber] Escenario de seguridad: " << escenario << "\n\n";

            // Inicializar el suscriptor con el escenario de seguridad
            payloadSubscriber mysub;
            if (!mysub.init(escenario))
            {
                std::cerr << "[Subscriber] Error fatal: no se pudo inicializar "
                          << "el participante DDS.\n"
                          << "  · Comprueba que los artefactos de seguridad existen "
                          << "(bash generate_security_artifacts.sh).\n"
                          << "  · Ejecuta el binario desde la raíz del proyecto.\n\n";
                return 1;
            }

            std::cout << "[Subscriber] Listo. Escuchando en 'payloadTopic'...\n"
                      << "[Subscriber] Salida CSV → SeqNum,PayloadSize(bytes),Latency(µs)\n\n";

            // Bucle principal del suscriptor: bloquea hasta que el usuario
            // pulse Enter (la lógica de recepción ocurre en el listener).
            mysub.run();

            break;
        }

        default:
            // No debería llegar aquí; cubierto por la comprobación inicial.
            print_usage(argv[0]);
            return 1;
    }

    return 0;
}