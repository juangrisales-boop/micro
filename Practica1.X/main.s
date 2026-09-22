PROCESSOR 18F4550              ; Define el microcontrolador objetivo
#include <xc.inc>              ; Incluye las definiciones de registros del compilador

; ==============================================================================
; CONFIGURACIÓN DE FUSIBLES DEL MICROCONTROLADOR
; ==============================================================================
config FOSC = INTOSC_EC        ; Utiliza el oscilador interno del PIC (salida de reloj en RA6)
config WDT = OFF               ; Desactiva el Perro Guardián (Watchdog Timer)
config LVP = OFF               ; Desactiva la programación en bajo voltaje para liberar el pin RB5
config PBADEN = OFF            ; Configura los pines del PORTB (RB0-RB4) como entradas/salidas digitales
config MCLRE = ON              ; Habilita el pin Master Clear (Reset externo activo en bajo)

; ==============================================================================
; MEMORIA RAM (DECLARACIÓN DE VARIABLES EN ACCESS BANK)
; ==============================================================================
psect udata_acs
temp_celsius:    DS 1          ; Variable para almacenar la temperatura medida en °C (1 byte)
temp_fahrenheit: DS 1          ; Variable para almacenar la temperatura convertida a °F (1 byte)
modo_pantalla:   DS 1          ; Bandera: 0 = Mostrar °C, 1 = Mostrar °F (1 byte)
decenas:         DS 1          ; Almacena el dígito de las decenas BCD a mostrar (1 byte)
unidades:        DS 1          ; Almacena el dígito de las unidades BCD a mostrar (1 byte)
delay_cnt1:      DS 1          ; Contador 1 para bucles de retardo (1 byte)
delay_cnt2:      DS 1          ; Contador 2 para bucles de retardo (1 byte)
temp_div:        DS 1          ; Variable auxiliar para el cálculo de división (1 byte)

; ==============================================================================
; VECTORES DE INTERRUPCIÓN Y RESET ABSOLUTOS
; ==============================================================================
psect resetVec, class=CODE, delta=1, abs
org 0x0000                     ; Dirección física 0x0000: Vector de Reset del sistema
resetVec:
    goto MAIN                  ; Salta al inicio del programa principal tras un reset

psect intCodeHi, class=CODE, delta=1, abs
org 0x0008                     ; Dirección física 0x0008: Vector de Interrupción de Alta Prioridad
intCodeHi:
    goto ISR_HIGH              ; Salta a la rutina de servicio de interrupción (ISR)

; ==============================================================================
; BLOQUE DE CÓDIGO PRINCIPAL Y DATOS
; ==============================================================================
psect code, class=CODE, delta=1, reloc=2

; --- TABLA DE CODIFICACIÓN PARA DISPLAY DE 7 SEGMENTOS (CÁTODO COMÚN) ---
TABLA_7SEG_DATA:
    db 0b00111111              ; Representación del número 0 en 7 segmentos (g,f,e,d,c,b,a)
    db 0b00000110              ; Representación del número 1
    db 0b01011011              ; Representación del número 2
    db 0b01001111              ; Representación del número 3
    db 0b01100110              ; Representación del número 4
    db 0b01101101              ; Representación del número 5
    db 0b01111101              ; Representación del número 6
    db 0b00000111              ; Representación del número 7
    db 0b01111111              ; Representación del número 8
    db 0b01101111              ; Representación del número 9

; --- INICIALIZACIÓN DEL SISTEMA ---
MAIN:
    movlw   0b01110000         ; Carga valor para configurar la velocidad del reloj a 8 MHz
    movwf   OSCCON, c          ; Guarda la configuración en el registro de control del oscilador

    call    CONFIG_PUERTOS     ; Inicializa pines como entradas o salidas
    call    CONFIG_INTERRUPCIONES ; Habilita las interrupciones externas y de temporizador
    call    CONFIG_ADC         ; Configura el convertidor Analógico-Digital
    call    CONFIG_TIMER0      ; Configura el temporizador para muestreo automático

    ; --- LECTURA INICIAL DEL SENSOR ---
    bsf     ADCON0, 1, c       ; Inicia la primera conversión ADC (Bit GO/DONE = 1)
ESPERAR_ADC_INIT:
    btfsc   ADCON0, 1, c       ; ¿Terminó la conversión ADC? (Bit GO/DONE == 0)
    goto    ESPERAR_ADC_INIT   ; Si no ha terminado, espera en bucle
    
    bcf     STATUS, 0, c       ; Limpia el bit de Acarreo (Carry) antes de rotar
    rrcf    ADRESH, w, c       ; Rota registros del ADC a la derecha para ajustar la escala
    rrcf    ADRESL, w, c       ; Pasa el resultado escalado al registro de trabajo W
    movwf   temp_celsius, c    ; Guarda la temperatura inicial en °C
    call    CALCULAR_FAHRENHEIT ; Realiza la conversión inicial a °F

; --- BUCLE PRINCIPAL (EJECUCIÓN CONTINUA) ---
MAIN_LOOP:
    call    CALCULAR_DIGITOS   ; Convierte la temperatura actual en Decenas y Unidades BCD
    call    MULTIPLEXAR_DISPLAYS ; Enciende y conmuta los displays alternadamente
    goto    MAIN_LOOP          ; Repite el bucle indefinidamente

; --- RUTINA PARA LEER LA TABLA DE 7 SEGMENTOS DESDE LA MEMORIA FLASH ---
TABLA_7SEG:
    andlw   0x0F               ; Enmascara el registro W para asegurar valores de 0 a 15
    movwf   TBLPTRL, c         ; Carga el índice en la parte baja del puntero de tabla
    movlw   low(TABLA_7SEG_DATA) ; Carga la dirección base baja de la tabla
    addwf   TBLPTRL, f, c      ; Suma la base con el índice
    movlw   high(TABLA_7SEG_DATA) ; Carga la dirección base alta de la tabla
    movwf   TBLPTRH, c         ; Asigna el byte alto al puntero
    btfsc   STATUS, 0, c       ; Si hubo acarreo en la suma previa...
    incf    TBLPTRH, f, c      ; Incrementa la parte alta del puntero
    clrf    TBLPTRU, c         ; Limpia el byte superior del puntero (21 bits)
    tblrd*                     ; Lee la memoria de programa en la posición apuntada
    movf    TABLAT, w, c       ; Copia el dato leído hacia el registro W
    return                     ; Retorna de la rutina

; ==============================================================================
; CONFIGURACIÓN DE PERIFÉRICOS
; ==============================================================================
CONFIG_PUERTOS:
    bsf     TRISB, 0, c        ; Configura RB0 como entrada digital (Botón INT0 / Alarma)
    bsf     TRISB, 1, c        ; Configura RB1 como entrada digital (Botón INT1 / Ventilador)
    bsf     TRISB, 2, c        ; Configura RB2 como entrada digital (Botón INT2 / Modo °C/°F)
    bsf     TRISA, 0, c        ; Configura RA0 como entrada analógica (Sensor LM35)

    clrf    TRISC, c           ; Configura todo el PORTC como salidas digitales (Control)
    clrf    TRISD, c           ; Configura todo el PORTD como salidas digitales (Segmentos 7SEG)
    clrf    LATC, c            ; Apaga todas las salidas del PORTC
    clrf    LATD, c            ; Apaga todas las salidas del PORTD
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c      ; Habilita las resistencias Pull-Up internas del PORTB
    
    bcf     INTCON2, 6, c      ; Configura INT0 para detectar flanco de bajada (Presionar botón)
    bcf     INTCON2, 5, c      ; Configura INT1 para detectar flanco de bajada
    bcf     INTCON2, 4, c      ; Configura INT2 para detectar flanco de bajada

    bcf     INTCON, 1, c       ; Limpia la bandera de interrupción de INT0 (INT0IF)
    bcf     INTCON3, 0, c      ; Limpia la bandera de interrupción de INT1 (INT1IF)
    bcf     INTCON3, 1, c      ; Limpia la bandera de interrupción de INT2 (INT2IF)

    bsf     INTCON, 4, c       ; Habilita la interrupción externa INT0
    bsf     INTCON3, 3, c      ; Habilita la interrupción externa INT1
    bsf     INTCON3, 4, c      ; Habilita la interrupción externa INT2
    bsf     INTCON, 7, c       ; Habilita el interruptor global de interrupciones (GIE)
    return

CONFIG_ADC:
    movlw   0b00001110         ; Configura AN0 como analógico y las demás entradas como digitales
    movwf   ADCON1, c          ; Guarda en el registro de control de pines del ADC
    movlw   0b10101010         ; Justificación Derecha, Tiempo de adquisición 12 TAD, Reloj Fosc/32
    movwf   ADCON2, c
    movlw   0b00000001         ; Selecciona canal AN0 y enciende el módulo ADC (ADON = 1)
    movwf   ADCON0, c
    return

CONFIG_TIMER0:
    movlw   0b11000111         ; Timer0 ON, 8 bits, reloj interno, Prescaler 1:256 (~32 ms)
    movwf   T0CON, c
    clrf    TMR0L, c           ; Reinicia el contador del Timer0 a cero
    bcf     INTCON, 2, c       ; Limpia la bandera de desbordamiento del Timer0 (TMR0IF)
    bsf     INTCON, 5, c       ; Habilita la interrupción por desbordamiento del Timer0
    return

; ==============================================================================
; CÁLCULOS Y MATEMÁTICAS (CONVERSIÓN °C A °F Y BCD)
; ==============================================================================
CALCULAR_FAHRENHEIT:
    movf    temp_celsius, w, c ; Copia la temperatura en °C al registro W
    rlncf   WREG, w, c         ; Multiplica por 2 usando rotación hacia la izquierda
    rlncf   WREG, w, c         ; Multiplica nuevamente por 2 (WREG = Celsius * 4)
    
    clrf    temp_div, c        ; Inicializa el cociente de la división en cero
DIV_LOOP:
    addlw   -5                 ; Resta 5 al valor acumulado
    btfss   STATUS, 0, c       ; Si el resultado es negativo (Carry == 0), termina la división
    goto    FIN_DIV
    incf    temp_div, f, c     ; Incrementa el cociente por cada resta exitosa
    goto    DIV_LOOP           ; Continúa restando

FIN_DIV:
    movf    temp_celsius, w, c ; Carga la temperatura base en Celsius
    addwf   temp_div, w, c     ; Suma el resultado de (4*C)/5 con C (Efecto: C * 1.8)
    addlw   32                 ; Le suma la constante 32 para completar la fórmula °F
    movwf   temp_fahrenheit, c ; Guarda la temperatura final convertida en °F
    return

CALCULAR_DIGITOS:
    btfsc   modo_pantalla, 0, c ; Evalúa la bandera de modo: ¿Esta activado el modo °F?
    goto    USAR_FAHRENHEIT     ; Si es 1, procesa la variable de Fahrenheit
    movf    temp_celsius, w, c  ; Si es 0, procesa la variable de Celsius
    goto    SEPARAR_DEC_UNI

USAR_FAHRENHEIT:
    movf    temp_fahrenheit, w, c ; Carga la temperatura en Fahrenheit a W

SEPARAR_DEC_UNI:
    clrf    decenas, c         ; Borra el registro de decenas
    movwf   unidades, c        ; Copia el valor total en el registro de unidades temporalmente

BUCLE_DEC:
    movlw   10                 ; Carga 10 en W
    subwf   unidades, w, c     ; Le resta 10 a las unidades
    btfss   STATUS, 0, c       ; ¿El resultado es menor que 0?
    goto    FIN_BCD            ; Si es menor que 10, finaliza la conversión
    movwf   unidades, c        ; Actualiza las unidades con la resta acumulada
    incf    decenas, f, c      ; Incrementa en 1 la cuenta de decenas
    goto    BUCLE_DEC          ; Repite la resta iterativa

FIN_BCD:
    return

; ==============================================================================
; MULTIPLEXADO Y CONTROL DE DISPLAYS
; ==============================================================================
MULTIPLEXAR_DISPLAYS:
    ; --- DISPLAY 1: DECENAS ---
    bcf     LATC, 1, c         ; Apaga el Display 2 (Unidades - RC1)
    movf    decenas, w, c      ; Carga el dígito de las decenas
    call    TABLA_7SEG         ; Obtiene la combinación de segmentos
    movwf   LATD, c            ; Envía los datos al PORTD
    bsf     LATC, 0, c         ; Enciende el Display 1 (Decenas - RC0)
    call    DELAY_DISPLAYS     ; Espera un tiempo para visibilidad del ojo humano

    ; --- DISPLAY 2: UNIDADES ---
    bcf     LATC, 0, c         ; Apaga el Display 1 (Decenas - RC0)
    movf    unidades, w, c     ; Carga el dígito de las unidades
    call    TABLA_7SEG         ; Obtiene la combinación de segmentos
    movwf   LATD, c            ; Envía los datos al PORTD
    bsf     LATC, 1, c         ; Enciende el Display 2 (Unidades - RC1)
    call    DELAY_DISPLAYS     ; Espera un tiempo para visibilidad
    return

DELAY_DISPLAYS:
    movlw   10                 ; Carga 10 iteraciones en el bucle externo
    movwf   delay_cnt1, c
LOOP_OUTER:
    movlw   100                ; Carga 100 iteraciones en el bucle interno
    movwf   delay_cnt2, c
LOOP_INNER:
    decfsz  delay_cnt2, f, c   ; Decrementa y salta cuando llegue a cero
    goto    LOOP_INNER
    decfsz  delay_cnt1, f, c
    goto    LOOP_OUTER
    return

; ==============================================================================
; RUTINA DE SERVICIO DE INTERRUPCIÓN (ISR) Y EVENTOS
; ==============================================================================
ISR_HIGH:
    btfsc   INTCON, 1, c       ; ¿Ocurrió la interrupción por el botón INT0 (RB0)?
    goto    ATENDER_INT0

    btfsc   INTCON3, 0, c      ; ¿Ocurrió la interrupción por el botón INT1 (RB1)?
    goto    ATENDER_INT1

    btfsc   INTCON3, 1, c      ; ¿Ocurrió la interrupción por el botón INT2 (RB2)?
    goto    ATENDER_INT2

    btfsc   INTCON, 2, c       ; ¿Ocurrió el desbordamiento del Timer0?
    goto    ATENDER_TIMER0

    retfie                     ; Retorna de la interrupción si fue una fuente no esperada

ATENDER_INT0:
    call    DELAY_DEBOUNCE     ; Filtra rebotes mecánicos del botón
    btfss   PORTB, 0, c        ; Verifica si el botón sigue presionado en cero lógico (GND)
    btg     LATC, 2, c         ; Alterna el estado de la salida de Alarma (RC2)
    bcf     INTCON, 1, c       ; Limpia la bandera de interrupción INT0IF
    retfie

ATENDER_INT1:
    call    DELAY_DEBOUNCE     ; Filtra rebotes mecánicos del botón
    btfss   PORTB, 1, c        ; Verifica si el botón sigue presionado en GND
    btg     LATC, 6, c         ; Alterna manualmente el estado del Ventilador (RC6)
    bcf     INTCON3, 0, c      ; Limpia la bandera de interrupción INT1IF
    retfie

ATENDER_INT2:
    call    DELAY_DEBOUNCE     ; Filtra rebotes mecánicos del botón
    btfss   PORTB, 2, c        ; Verifica si el botón sigue presionado en GND
    btg     modo_pantalla, 0, c ; Cambia la bandera entre mostrar Celsius (0) y Fahrenheit (1)
    bcf     INTCON3, 1, c      ; Limpia la bandera de interrupción INT2IF
    retfie

ATENDER_TIMER0:
    bcf     INTCON, 2, c       ; Limpia la bandera de desbordamiento TMR0IF
    
    ; --- MUESTREO REGULAR Y LECTURA DEL ADC ---
    bcf     STATUS, 0, c       ; Limpia bit Carry antes de rotar
    rrcf    ADRESH, w, c       ; Rota registro alto del ADC
    rrcf    ADRESL, w, c       ; Rota registro bajo del ADC
    movwf   temp_celsius, c    ; Actualiza la lectura de temperatura
    call    CALCULAR_FAHRENHEIT ; Re-calcula la equivalencia en Fahrenheit

    ; --- CONTROL DE VENTILADOR CON HISTÉRESIS DE TEMPERATURA ---
    btfsc   LATC, 6, c         ; ¿El ventilador ya está encendido en este momento?
    goto    COMPROBAR_APAGADO  ; Si está ON, verifica si corresponde apagarlo

COMPROBAR_ENCENDIDO:
    movlw   35                 ; Carga el umbral superior de encendido (35 °C)
    subwf   temp_celsius, w, c ; Resta el umbral a la temperatura actual
    btfsc   STATUS, 0, c       ; Si Temp >= 35 (Carry = 1)
    bsf     LATC, 6, c         ; Enciende la salida del ventilador en RC6
    goto    FIN_CONTROL_VENT

COMPROBAR_APAGADO:
    movlw   33                 ; Carga el umbral inferior de apagado (33 °C)
    subwf   temp_celsius, w, c ; Resta el umbral a la temperatura actual
    btfss   STATUS, 0, c       ; Si Temp < 33 (Carry = 0)
    bcf     LATC, 6, c         ; Apaga la salida del ventilador en RC6

FIN_CONTROL_VENT:
    bsf     ADCON0, 1, c       ; Inicia una nueva conversión ADC para el próximo ciclo
    retfie

; --- RUTINA DE RETARDILLO PARA ANTIRREBOTE DE BOTONES (DEBOUNCE OPTIMIZADO) ---
DELAY_DEBOUNCE:
    movlw   15                 ; Bucle externo corto para respuesta rápida
    movwf   delay_cnt1, c
D_L1:
    movlw   50                 ; Bucle interno de retardo
    movwf   delay_cnt2, c
D_L2:
    decfsz  delay_cnt2, f, c   ; Decrementa contador 2
    goto    D_L2
    decfsz  delay_cnt1, f, c   ; Decrementa contador 1
    goto    D_L1
    return

END resetVec                   