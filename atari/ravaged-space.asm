;=============================================================================
; ravaged-space.asm - self-contained VBXE survival game. Assemble with MADS:
;
;       mads atari/ravaged-space.asm -o:atari/ravaged-space.xex
;
; What it shows, in the order the code does it:
;
;   1. There is no ANTIC picture at all. Screen DMA is switched off and the whole
;      320x200 image is a VBXE overlay framebuffer at VRAM $000000, one byte per
;      pixel, 256 colours out of VBXE palette #1. That is exactly how the UFO port
;      runs -- no character mode, no display list, no playfield.
;
;   2. Text is not a hardware character mode either. A font "sheet" lives in VRAM
;      and each glyph is blitted into the framebuffer by the VBXE blitter, one
;      blit per character. To keep this file free of data blobs, the sheet is
;      built at runtime from the Atari OS ROM charset at $E000 (see font_expand):
;      every glyph pixel becomes 255, every gap 0. Blitting with AND = colour then
;      stamps the glyph in any palette index you like -- one font, any colour.
;      (The real game bakes its font from the original UFO's SMALLSET.DAT the same
;      way, plus a second copy with the original two-tone colours baked in.)
;
;   3. The window is a filled rectangle for the border and a second, inset one for
;      the face. The game blits a crop of the original .SCR artwork in there
;      instead, but the geometry is this.
;
;   4. The up/down icons are the real thing: a 1:1 transcription of OpenXcom's
;      ArrowButton::draw() (src/Interface/ArrowButton.cpp:94-303). An X-COM arrow
;      button is NOT a bare triangle -- it is a bevelled box (top/left _color+2,
;      bottom/right _color+5, face _color+4, three corner pixels poked by hand)
;      with a 9px triangle and a 3x3 stem inside it, all in _color+1. Holding it
;      down runs ImageButton::mousePress -> invert(_color+3), which maps a pixel
;      p to 2*(_color+3)-p; for _color+N that is simply _color+(6-N). So the same
;      five colours, read backwards, give you the pressed look for free.
;
;   Controls: joystick 0 up/down changes the number (click, then auto-repeat with
;   acceleration, like the original). There is no exit -- switch the machine off.
;
; Needs a VBXE. Without one it just flashes the border and stops.
;=============================================================================

; ---- Atari OS / hardware ----
SDMCTL   = $022F                ; OS shadow of DMACTL; the VBI copies it every frame
COLOR4   = $02C8
CH       = $02FC                ; OS keyboard scan-code shadow, $FF = no key
CHARSET  = $E000                ; OS ROM charset: 128 glyphs x 8 bytes, internal order
PORTA    = $D300                ; joystick 0 in bits 0..3 (up, down, left, right; 0 = pushed)
STRIG0   = $D010
DMACTL   = $D400
VCOUNT   = $D40B

; ---- VBXE ----
VBXE_VCTL       = $D640
VBXE_XDL0       = $D641
VBXE_XDL1       = $D642
VBXE_XDL2       = $D643
VBXE_CSEL       = $D644
VBXE_PSEL       = $D645
VBXE_CR         = $D646
VBXE_CG         = $D647
VBXE_CB         = $D648
VBXE_BL_ADR0    = $D650
VBXE_BL_ADR1    = $D651
VBXE_BL_ADR2    = $D652
VBXE_BLITTER    = $D653
VBXE_MEMAC_CTRL = $D65E
VBXE_BANK_SEL   = $D65F

VC_XDL_ON = $01
VC_XCOLOR = $02
MC_CPU    = $08
BANK_EN   = $80

MEMW      = $9000               ; the 4K CPU window onto VRAM (MEMAC-A)
SCR_W     = 320
SCR_H     = 200

BANK_XDL  = $7F                 ; XDL at $07F000, blitter control block at $07F100
BCB_OFF   = $100
FONT_BANK = $38                 ; font sheet at $038000: 64 glyphs x 8x8, padded to 64 B
FONT_HI   = $80                 ; so glyph addr = $038000 + (gi<<6)
FONT_B2   = $03
ICON_BANK = $39                 ; seven coloured 8x8 system icons at $039000
ICON_HI   = $90
ICON_B2   = $03

; ---- palette indices. Deliberately laid out like an X-COM 16-colour ramp: the
;      LOWER the index the lighter the colour, so the widget's _color+1..+5 come
;      out light-to-dark and its base colour can simply be 0. ----
C_ARROW   = 1                   ; _color+1  arrow + top-left corner pixel
C_BEV_LT  = 2                   ; _color+2  top/left bevel
C_OUTLINE = 3                   ; _color+3  (the small arrow's outline; unused here)
C_FACE    = 4                   ; _color+4  button face
C_BEV_DK  = 5                   ; _color+5  bottom/right bevel
C_BORDER  = 6                   ; window border
C_WIN     = 7                   ; window face
C_TEXT    = 8
C_TITLE   = 9
C_VALUE   = 10
C_HINT    = 11
C_ONLINE  = 12
C_DEGRADE = 13
C_OFFLINE = 14
C_SELECT  = 15
C_COOLDOWN = 16
C_LOADPROG = 17
C_ICON_BASE = 18
C_NOISE   = 25                  ; faint phosphor grain; icon colours stay 18..24

; ---- game layout ----
WIN_X   = 4
WIN_Y   = 3
WIN_W   = 312
WIN_H   = 194
TXT_X   = 12
TITLE_Y = 8
ROW_X   = 12
ROW_Y   = 32
ROW_H   = 16
BAR_X   = 32
BAR_W   = 80
VAL_X   = 0                    ; numeric value removed; ten boxes carry status
ACT_X   = 116
HINT_X  = 12
HINT_Y  = 176

AW_W    = 13                    ; ArrowButton(ARROW_BIG_UP, 13, 14, ...)
AW_H    = 14
AW_X    = WIN_X+192
AW_UP_Y = WIN_Y+36
AW_DN_Y = AW_UP_Y+20            ; ResearchInfoState.cpp:80-81 spaces its pair 20px apart

REP_DELAY = 16                  ; frames held before the first auto-repeat
REP_FIRST = 6                   ; initial repeat interval, in frames
REP_MIN   = 2                   ; fastest interval after acceleration

; ---- zero page (spare OS bytes) ----
srcp    = $CB                   ; 2 - font_expand source
dstp    = $CD                   ; 2 - font_expand destination
opp     = $CF                   ; 2 - aw_run's op-list pointer
; $D4..$D9 is the OS floating-point scratch (FR0). We never call the FP pack, so
; it is ours; $D2/$D3 are less reliably free, hence the jump.
calc_out = $D4                  ; 3 - 24-bit VRAM address
txt_ptr = $D7                   ; 2 - draw_text's string

        org $2000

;=============================================================================
; main
;=============================================================================
.proc main
        jsr detect_vbxe
        bcs ?ok
        lda #$34                ; no VBXE -> red border, park
        sta COLOR4
        jmp *
?ok     lda #0
        sta SDMCTL              ; ANTIC playfield off. Setting the SHADOW is what
        sta DMACTL              ;   makes it stick: the OS VBI reloads DMACTL from it.
        lda #$90+MC_CPU         ; MEMAC-A: map a 4K VRAM window at $9000, CPU side
        sta VBXE_MEMAC_CTRL
        lda #0
        sta VBXE_VCTL
        jsr setup_xdl
        jsr blit_init
        jsr load_pal
        jsr font_expand
        jsr icons_expand
        jsr enable_display
        jsr game_init
        jsr draw_screen
        jmp loop
.endp

;=============================================================================
; loop - one pass per PAL/NTSC frame. Input is edge-triggered; timers and the
; recurring ship load continue in real time.
;=============================================================================
selected dta 0
old_stick dta 15
old_fire dta 1
frame50  dta 0
load_sec dta 20
game_mode dta 0                ; 0 playing, 1 won, 2 lost
message_timer dta 0
cooldown_ready dta 0

; health/status points, 0..10. Ordering matches all tables below.
health   dta 2,7,9,2,2,1,3
cooldown dta 0,0,0,0,0,0,0
cooldown_frac dta 0,0,0,0,0,0,0
cooldown_full dta 10,10,10,10,10,10,10
unlocked dta 1,0,0,0,0,0,0
clicks   dta 0,0,0,0,0,0,0
levels   dta 0,0,0,0
load_pwr dta 0
load_lif dta 1
system_load_pwr dta 0,0,0,0,0,0,0
system_load_lif dta 0,1,0,0,0,0,0
amount_mask dta 0              ; bits 0..2: Power/Life Support/Processing
auto_mask dta 0
speed_mask dta 0
modal_type dta 0               ; 0 none, 1 amount, 2 auto, 3 speed
amount_opened dta 0
special_available dta 0,0,0,0,0,0,0
special_done dta 0,0,0,0,0,0,0
special_sec dta 0,0,0,0,0,0,0
special_frac dta 0,0,0,0,0,0,0
story_type dta 0
failure_system dta $FF

; Per-action immediate deltas. Positive values repair the selected system;
; costs are subtracted explicitly in perform_action.
gain_tab dta 2,1,3,2,2,3,2
base_gain dta 2,1,3,2,2,3,2
cost_pwr dta 0,1,1,2,1,3,1
cost_lif dta 0,0,0,0,0,1,0
cost_prc dta 1,0,0,2,0,1,1
base_cost_pwr dta 0,1,1,2,1,3,1
base_cost_prc dta 1,0,0,2,0,1,1
bit_tab  dta 1,2,4,8,16,32,64

names_lo dta <s_power,<s_life,<s_process,<s_engineer,<s_guidance,<s_engines,<s_sensors
names_hi dta >s_power,>s_life,>s_process,>s_engineer,>s_guidance,>s_engines,>s_sensors

.proc loop
        jsr wait_frame
        lda modal_type
        beq ?game
        jsr read_modal_keyboard
        jmp loop
?game
        lda story_type
        beq ?normal
        jsr read_story_keyboard
        jmp loop
?normal
        lda game_mode
        bne ?restart
        jsr tick_game
        jsr read_keyboard
        jsr read_input
        jmp loop
?restart
        lda STRIG0
        cmp old_fire
        beq ?store
        cmp #0
        bne ?store
        jsr game_init
        jsr draw_screen
?store  lda STRIG0
        sta old_fire
        jmp loop
.endp

.proc game_init
        ldx #6
?copy   lda initial_health,x
        sta health,x
        lda #0
        sta cooldown,x
        sta cooldown_frac,x
        sta clicks,x
        sta unlocked,x
        sta system_load_pwr,x
        sta system_load_lif,x
        sta special_available,x
        sta special_done,x
        sta special_sec,x
        sta special_frac,x
        lda #10
        sta cooldown_full,x
        dex
        bpl ?copy
        lda #1
        sta unlocked
        sta load_lif
        sta system_load_lif+1
        lda #0
        sta selected
        sta frame50
        sta game_mode
        sta load_pwr
        sta amount_mask
        sta auto_mask
        sta speed_mask
        sta modal_type
        sta amount_opened
        sta story_type
        sta old_stick
        lda #$FF
        sta failure_system
        lda #4
        sta load_sec
        ldx #6
?gain   lda base_gain,x
        sta gain_tab,x
        lda base_cost_pwr,x
        sta cost_pwr,x
        lda base_cost_prc,x
        sta cost_prc,x
        dex
        bpl ?gain
        lda #1
        sta old_fire
        rts
.endp
initial_health dta 2,7,9,2,2,1,3

; Direct action keys: P/L/O/E/G/N/S. Modification keys: A/U/D.
; Values are Atari OS CH scan codes (unshifted letters).
.proc read_keyboard
        lda CH
        cmp #$FF
        beq ?done
        and #$3F                ; ignore Shift/Control modifier bits
        sta ?key
        lda #$FF
        sta CH
        lda ?key
        cmp #$0A                ; P - Power
        beq ?power
        cmp #$00                ; L - Life Support
        beq ?life
        cmp #$08                ; O - Processing
        beq ?processing
        cmp #$2A                ; E - Engineering
        beq ?engineering
        cmp #$3D                ; G - Guidance
        beq ?guidance
        cmp #$23                ; N - Engines
        beq ?engines
        cmp #$3E                ; S - Sensors
        beq ?sensors
        cmp #$3F                ; A - Amount modification
        beq ?amount
        cmp #$0B                ; U - Automation modification
        beq ?auto
        cmp #$3A                ; D - Speed modification
        beq ?speed
?done   rts
?power lda #0
        beq ?action
?life  lda #1
        bne ?action
?processing lda #2
        bne ?action
?engineering lda #3
        bne ?action
?guidance lda #4
        bne ?action
?engines lda #5
        bne ?action
?sensors lda #6
?action sta ?action_idx
        tax
        jsr action_active
        bcc ?done
        lda ?action_idx
        sta selected
        jsr draw_rows
        jmp perform_action
?amount jmp buy_amount
?auto   jmp buy_auto
?speed  jmp buy_speed
?key    dta 0
?action_idx dta 0
.endp

.proc read_modal_keyboard
        lda CH
        cmp #$FF
        beq ?done
        and #$3F
        sta ?key
        lda #$FF
        sta CH
        lda ?key
        cmp #$1C                ; Escape
        beq ?cancel
        cmp #$0A                ; P - Power
        beq ?power
        cmp #$00                ; L - Life Support
        beq ?life
        cmp #$08                ; O - Processing
        beq ?processing
?done   rts
?cancel lda #0
        sta modal_type
        jmp draw_screen
?power ldx #0
        beq ?select
?life  ldx #1
        bne ?select
?processing ldx #2
?select jmp select_modification
?key    dta 0
.endp

.proc read_story_keyboard
        lda STRIG0
        beq ?close
        lda CH
        cmp #$FF
        beq ?done
        and #$3F
        cmp #$1C                ; Escape
        beq ?close
        cmp #$0C                ; Return
        bne ?done
?close  lda #$FF
        sta CH
        lda #0
        sta story_type
        jmp draw_screen
?done   rts
.endp

amount_upgraded dta 5,3,7
.proc select_modification      ; X=resource system 0..2
        stx ?system
        lda bit_tab,x
        sta ?bit
        lda modal_type
        cmp #1
        bne ?auto
        lda amount_mask
        and ?bit
        bne ?done
        lda amount_mask
        ora ?bit
        sta amount_mask
        ldx ?system
        lda amount_upgraded,x
        sta gain_tab,x
        cpx #0
        bne ?processing_cost
        lda #2
        sta cost_prc
?processing_cost
        cpx #2
        bne ?close
        lda #2
        sta cost_pwr+2
        bne ?close
?auto   cmp #2
        bne ?speed
        lda auto_mask
        and ?bit
        bne ?done
        lda auto_mask
        ora ?bit
        sta auto_mask
        bne ?close
?speed  lda speed_mask
        and ?bit
        bne ?done
        lda speed_mask
        ora ?bit
        sta speed_mask
        ldx ?system
        lda #5
        sta cooldown_full,x
        lda cooldown,x
        beq ?close
        clc
        adc #1
        lsr
        sta cooldown,x
        lda cooldown_frac,x
        clc
        adc #1
        lsr
        sta cooldown_frac,x
?close  lda #0
        sta modal_type
        jmp draw_screen
?done   rts
?system dta 0
?bit    dta 0
.endp

.proc read_input
        lda PORTA
        and #15
        cmp old_stick
        beq ?fire
        sta old_stick
        and #1
        bne ?down
        lda selected
        beq ?draw
        dec selected
        jmp ?draw
?down   lda old_stick
        and #2
        bne ?left
        lda selected
        cmp #6
        beq ?draw
        inc selected
        jmp ?draw
?left   lda old_stick
        and #4
        bne ?right
        jsr buy_amount
        jmp ?draw
?right  lda old_stick
        and #8
        bne ?fire
        jsr buy_speed
?draw   jsr draw_rows
        jsr draw_footer
?fire   lda STRIG0
        cmp old_fire
        beq ?done
        sta old_fire
        cmp #0
        bne ?done
        jsr perform_action
?done   rts
.endp

.proc perform_action
        ldx selected
        jsr action_active
        bcs ?active
        jmp ?done
?active
        lda special_available,x
        beq ?normal_action
        lda #20
        sta special_sec,x
        lda #50
        sta special_frac,x
        jsr draw_rows
        jmp draw_footer
?normal_action
        lda health+2
        cmp cost_prc,x
        bcs ?sub_prc
        lda #0
        beq ?store_prc
?sub_prc
        sec
        sbc cost_prc,x
?store_prc
        sta health+2
        lda health
        cmp cost_pwr,x
        bcs ?sub_pwr
        lda #0
        beq ?store_pwr
?sub_pwr
        sec
        sbc cost_pwr,x
?store_pwr
        sta health
        lda health+1
        cmp cost_lif,x
        bcs ?sub_lif
        lda #0
        beq ?store_lif
?sub_lif
        sec
        sbc cost_lif,x
?store_lif
        sta health+1
        lda health,x
        clc
        adc gain_tab,x
        cmp #11
        bcc ?gainok
        lda #10
?gainok sta health,x
        inc clicks,x
        jsr add_system_load
        lda #10
        sta cooldown_full,x
        lda bit_tab,x
        and speed_mask
        beq ?normal_cd
        lda #5
        sta cooldown_full,x
?normal_cd
        lda cooldown_full,x
        sta cooldown,x
        lda #50
        sta cooldown_frac,x
        jsr update_progress
        jsr update_specials
        jsr check_end
        lda game_mode
        bne ?done
        jsr draw_rows
        jsr draw_footer
?done
        rts
?deny   rts
.endp

.proc add_system_load
        ldx selected
        cpx #3
        bcc ?r
        lda clicks,x
        cmp #1
        bne ?second
        inc load_pwr
        inc system_load_pwr,x
        cpx #3
        beq ?life
        cpx #5
        bne ?r
?life   inc load_lif
        inc system_load_lif,x
        rts
?second cmp #2
        bne ?third
        cpx #3
        beq ?life2
        cpx #5
        bne ?r
        inc load_pwr
        inc system_load_pwr,x
        rts
?life2  inc load_lif
        inc system_load_lif,x
        rts
?third  cmp #3
        bne ?r
        cpx #3
        bne ?guidance4
        inc load_pwr
        inc system_load_pwr,x
        lda load_lif
        clc
        adc #3
        sta load_lif
        lda system_load_lif,x
        clc
        adc #3
        sta system_load_lif,x
        rts
?guidance4 cpx #4
        bne ?engines4
        inc load_pwr
        inc system_load_pwr,x
        rts
?engines4 cpx #5
        bne ?r
        lda load_pwr
        clc
        adc #3
        sta load_pwr
        lda system_load_pwr,x
        clc
        adc #3
        sta system_load_pwr,x
?r      rts
.endp

.proc action_denied
        lda #50
        sta message_timer
        jmp draw_denied
.endp

.proc action_active            ; X=system, C=1 only when shortcut can act now
        lda special_available,x
        beq ?normal
        lda special_sec,x
        bne ?no
        sec
        rts
?normal
        lda unlocked,x
        beq ?no
        lda cooldown,x
        bne ?no
        cpx #3
        bcc ?yes
        lda clicks,x
        cmp #3
        bcs ?no
?yes
        sec
        rts
?no     clc
        rts
.endp

.proc update_progress
        lda clicks
        cmp #2
        bcc ?r
        lda #1
        sta unlocked+1
        lda clicks+1
        cmp #2
        bcc ?r
        sta unlocked+2
        sta unlocked+3
        lda amount_opened
        beq ?r
        lda #1
        sta unlocked+4
        sta unlocked+5
        sta unlocked+6
?r      rts
.endp

.proc update_specials
        lda clicks+6
        cmp #1
        bcc ?guidance
        lda special_done+6
        bne ?guidance
        lda #1
        sta special_available+6
?guidance
        lda clicks+4
        cmp #2
        bcc ?engines
        lda special_done+6
        beq ?engines
        lda special_done+4
        bne ?engines
        lda #1
        sta special_available+4
?engines
        lda clicks+5
        cmp #2
        bcc ?engineering
        lda special_done+4
        beq ?engineering
        lda special_done+5
        bne ?engineering
        lda #1
        sta special_available+5
?engineering
        lda clicks+3
        cmp #2
        bcc ?done
        lda special_done+5
        beq ?done
        lda special_done+3
        bne ?done
        lda #1
        sta special_available+3
?done   rts
.endp

.proc buy_amount
        lda #1
        jmp open_modification
.endp

.proc buy_auto
        lda #2
        jmp open_modification
.endp

.proc buy_speed
        lda #3
        jmp open_modification
.endp

mod_check_type dta 0
mod_check_mask dta 0
.proc modification_available  ; A=type, C=1 if another resource may be chosen
        sta mod_check_type
        cmp #1
        bne ?auto
        lda amount_mask
        ldx #3
        bne ?check
?auto   cmp #2
        bne ?speed
        lda auto_mask
        ldx #4
        bne ?check
?speed  lda speed_mask
        ldx #5
?check  sta mod_check_mask
        cmp #7
        beq ?no
        lda clicks,x
        cmp #4
        bcc ?capacity
        lda #3
?capacity sta ?cap
        lda mod_check_mask
        ldx #0
?count  lsr
        bcc ?next
        inx
?next   cmp #0
        bne ?count
        cpx ?cap
        bcs ?no
        sec
        rts
?no     clc
        rts
?cap    dta 0
.endp

.proc open_modification       ; A=type
        sta mod_check_type
        jsr modification_available
        bcc ?done
        lda mod_check_type
        sta modal_type
        cmp #1
        bne ?draw
        lda #1
        sta amount_opened
        jsr update_progress
?draw
        jmp draw_modification_modal
?done   rts
.endp

.proc tick_game
        jsr tick_cooldowns
        jsr tick_specials
        jsr run_auto_actions
        jsr draw_progress
        inc frame50
        lda frame50
        cmp #50
        bcc ?r
        lda #0
        sta frame50
        dec load_sec
?load   lda load_sec
        ; draw_progress already updates the narrow load strips every frame.
        ; Repainting every complete row once per second made the live columns
        ; visibly flash even though no row content had changed.
        bne ?r
        lda #20
        sta load_sec
        lda health
        sec
        sbc load_pwr
        bcs ?p
        lda #0
?p      sta health
        lda health+1
        sec
        sbc load_lif
        bcs ?l
        lda #0
?l      sta health+1
        jsr check_end
        lda game_mode
        bne ?r
        jsr draw_rows
        jsr draw_footer
?r      rts
.endp

.proc tick_specials
        ldx #6
?loop   lda special_sec,x
        beq ?next
        dec special_frac,x
        bne ?next
        dec special_sec,x
        beq ?complete
        lda #50
        sta special_frac,x
        bne ?next
?complete
        stx ?system
        lda #0
        sta special_available,x
        lda #1
        sta special_done,x
        txa
        clc
        adc #1
        sta story_type
        cpx #3
        bne ?advance
        lda #10
        sta gain_tab
        lda #0
        sta cost_prc
?advance jsr update_specials
        ldx ?system
        jsr draw_story_modal
?next   dex
        cpx #2
        bne ?loop
        rts
?system dta 0
.endp

.proc tick_cooldowns
        lda #0
        sta cooldown_ready
        ldx #6
?loop   lda cooldown,x
        beq ?next
        dec cooldown_frac,x
        bne ?next
        dec cooldown,x
        bne ?reload
        inc cooldown_ready
        jmp ?next
?reload
        lda #50
        sta cooldown_frac,x
?next   dex
        bpl ?loop
        lda cooldown_ready
        beq ?done
        jsr draw_rows
?done
        rts
.endp

auto_idx dta 0
auto_selected dta 0
.proc run_auto_actions
        lda selected
        sta auto_selected
        ldx #0
?loop   stx auto_idx
        lda bit_tab,x
        and auto_mask
        beq ?next
        jsr action_active
        bcc ?next
        ldx auto_idx
        stx selected
        jsr perform_action
?next   ldx auto_idx
        inx
        cpx #3
        bne ?loop
        lda auto_selected
        sta selected
        rts
.endp

.proc check_end
        ldx #6
?loss   lda health,x
        beq ?lose
        dex
        bpl ?loss
        ldx #3
?win    lda health+3,x
        cmp #8
        bcc ?r
        dex
        bpl ?win
        lda #1
        sta game_mode
        jsr draw_end
?r      rts
?lose   lda #2
        sta game_mode
        stx failure_system
        jsr draw_end
        rts
.endp

; Run the game update at the start of the bottom vertical blank.  Returning
; immediately after the beam wrapped used to repaint the framebuffer while its
; live rows were being scanned, producing visible tearing/flashes.
.proc wait_frame
?visible lda VCOUNT
        cmp #124
        bcs ?visible            ; finish the current blank interval first
?blank  lda VCOUNT
        cmp #124
        bcc ?blank              ; wait for the next bottom blank interval
        rts
.endp

;=============================================================================
; VBXE bring-up
;=============================================================================
.proc detect_vbxe               ; C=1 if a VBXE answers at either core address
        lda VBXE_VCTL
        cmp #$10
        beq ?yes
        lda $D740
        cmp #$10
        beq ?yes
        clc
        rts
?yes    sec
        rts
.endp

; The XDL (VBXE's own display list): 8 overscan lines, then 200 active lines of a
; linear 320-byte-stride overlay reading VRAM $000000 through palette #1.
.proc setup_xdl
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        ldx #xdl_len-1
?l      lda xdl_data,x
        sta MEMW,x
        dex
        bpl ?l
        rts
.endp
xdl_data
        dta $74,$08             ; overscan block, OVOFF
        dta 7                   ; 8 lines
        dta $00,$00,$00         ; overlay address
        dta $40,$01             ; stride 320
        dta $11,$FF             ; overlay attributes
        dta $62,$88             ; GMON|RPTL|OVADR|OVATT|END
        dta SCR_H-1             ; 200 lines
        dta $00,$00,$00         ; framebuffer at VRAM $000000
        dta $40,$01             ; stride 320
        dta $11,$FF
xdl_len = * - xdl_data

.proc enable_display
        lda #VC_XDL_ON+VC_XCOLOR
        sta VBXE_VCTL
        lda #$00                ; XDL at $07F000
        sta VBXE_XDL0
        lda #$F0
        sta VBXE_XDL1
        lda #$07
        sta VBXE_XDL2
        rts
.endp

; load_pal: (index, r, g, b) quads into VBXE palette #1, terminated by $FF.
;   Writing the blue register auto-advances CSEL, but we set it per colour anyway
;   because the table is sparse.
.proc load_pal
        lda #1
        sta VBXE_PSEL
        ldx #0
?l      lda pal_tab,x
        cmp #$FF
        beq ?done
        sta VBXE_CSEL
        lda pal_tab+1,x
        sta VBXE_CR
        lda pal_tab+2,x
        sta VBXE_CG
        lda pal_tab+3,x
        sta VBXE_CB
        txa
        clc
        adc #4
        tax
        jmp ?l
?done   rts
.endp
pal_tab
        dta 0,   1,  7,  4      ; near-black CRT surround
        dta 1, 179,255,199      ; _color+1  bright phosphor arrow
        dta 2,  83,255,139      ; _color+2  bevel light
        dta 3,  45,200,103      ; _color+3  invert pivot
        dta 4,  14, 82, 45      ; _color+4  button face
        dta 5,   4, 36, 19      ; _color+5  bevel dark
        dta 6,  31,184, 97      ; neon-green window border
        dta 7,   3, 19, 11      ; dark-green window face
        dta 8, 130,245,167      ; phosphor text
        dta 9, 183,255,202      ; bright title
        dta 10,141,255,174      ; active value
        dta 11, 55,141, 89      ; dim hint
        dta 12, 80,255,134      ; online
        dta 13,183,217, 74      ; degraded
        dta 14,255,110, 85      ; offline/destroyed
        dta 15, 13, 59, 35      ; selected row
        dta 16, 20, 82, 47      ; animated action cooldown
        dta 17, 13, 62, 37      ; animated load cycle
        dta 18,248,208, 96      ; power bolt
        dta 19,232, 92,104      ; life-support heart
        dta 20,232,160, 96      ; processing core
        dta 21,184,192,204      ; engineering wrench
        dta 22,112,200,192      ; guidance robot
        dta 23,232,144, 56      ; engines rocket
        dta 24,144,158,216      ; sensors dish
        dta 25, 10, 46, 25      ; low-contrast CRT colour noise
        dta $FF

;=============================================================================
; font_expand - OS ROM charset -> an 8-bit "mask" font sheet in VRAM $038000.
;   ASCII 32..95 maps to Atari internal codes 0..63 by simply subtracting 32, so
;   glyph gi lives at CHARSET + gi*8 (8 bytes, 1 bit per pixel, MSB = leftmost).
;   Each is expanded to 8x8 bytes of 255/0 and padded to a 64-byte cell, so the
;   blitter's source address is base + (gi<<6) with no multiply. 64 cells x 64 B
;   is exactly one 4K bank, which is why the whole sheet fits one window select.
;=============================================================================
rowi    dta 0
dsti    dta 0
bits    dta 0

.proc font_expand
        lda #BANK_EN+FONT_BANK
        sta VBXE_BANK_SEL
        lda #<CHARSET
        sta srcp
        lda #>CHARSET
        sta srcp+1
        lda #<MEMW
        sta dstp
        lda #>MEMW
        sta dstp+1
        ldx #0                  ; glyph counter
?glyph  lda #0
        sta rowi
        sta dsti
?row    ldy rowi
        lda (srcp),y
        sta bits
        ldy #8                  ; 8 pixels, MSB first
?col    asl bits
        lda #0
        bcc ?zero
        lda #255                ; a set bit becomes 255 -> blitter AND=colour tints it
?zero   sty ?sy
        ldy dsti
        sta (dstp),y
        ldy ?sy
        inc dsti
        dey
        bne ?col
        inc rowi
        lda rowi
        cmp #8
        bne ?row
        lda srcp                ; next glyph: source +8, destination +64
        clc
        adc #8
        sta srcp
        bcc ?nc
        inc srcp+1
?nc     lda dstp
        clc
        adc #64
        sta dstp
        bcc ?nd
        inc dstp+1
?nd     inx
        cpx #64
        bne ?glyph
        lda #0
        sta VBXE_BANK_SEL
        rts
?sy     dta 0
.endp

; Seven custom 8x8 icons, shared pixel-for-pixel with src/game.js. They are
; expanded once into coloured VBXE sprites; zero remains transparent.
icon_bits
        dta $18,$18,$30,$7C,$18,$30,$20,$00 ; power: bolt
        dta $66,$FF,$FF,$7E,$3C,$18,$00,$00 ; life support: heart
        dta $7E,$42,$5A,$42,$5A,$42,$7E,$00 ; processing: core
        dta $C3,$66,$3C,$18,$38,$60,$C0,$00 ; engineering: wrench
        dta $18,$7E,$DB,$FF,$BD,$7E,$42,$00 ; guidance: robot
        dta $18,$3C,$7E,$5A,$5A,$3C,$66,$00 ; engines: rocket
        dta $06,$0C,$58,$30,$30,$7E,$18,$00 ; sensors: dish
icon_cols dta 18,19,20,21,22,23,24
icon_idx  dta 0
icon_rows dta 0
icon_cols_left dta 0

.proc icons_expand
        lda #BANK_EN+ICON_BANK
        sta VBXE_BANK_SEL
        lda #<icon_bits
        sta srcp
        lda #>icon_bits
        sta srcp+1
        lda #<MEMW
        sta dstp
        lda #>MEMW
        sta dstp+1
        lda #0
        sta icon_idx
?icon   lda #0
        sta icon_rows
?row    ldy #0
        lda (srcp),y
        sta bits
        inc srcp
        bne ?src_ok
        inc srcp+1
?src_ok lda #8
        sta icon_cols_left
?pixel  asl bits
        lda #0
        bcc ?store
        ldx icon_idx
        lda icon_cols,x
?store  ldy #0
        sta (dstp),y
        inc dstp
        bne ?dst_ok
        inc dstp+1
?dst_ok dec icon_cols_left
        bne ?pixel
        inc icon_rows
        lda icon_rows
        cmp #8
        bne ?row
        inc icon_idx
        lda icon_idx
        cmp #7
        bne ?icon
        lda #0
        sta VBXE_BANK_SEL
        rts
.endp

;=============================================================================
; VBXE blitter. One blitter control block at VRAM $07F100; do_blit refills it and
;   pulls the trigger. Fills are just blits with AND=0 and XOR=colour.
;=============================================================================
bl_src  dta 0,0,0
bl_ssy  dta a(0)
bl_ssx  dta 0
bl_dst  dta 0,0,0
bl_dsy  dta a(0)
bl_dsx  dta 0
bl_w    dta a(0)                ; width-1
bl_h    dta 0                   ; height-1
bl_and  dta 0
bl_xor  dta 0
bl_mode dta 0                   ; 0 = opaque, 1 = transparent (source 0 = leave alone)

.proc blit_init                 ; point the blitter at the BCB once; it never moves
        lda #<BCB_OFF
        sta VBXE_BL_ADR0
        lda #$F1
        sta VBXE_BL_ADR1
        lda #$07
        sta VBXE_BL_ADR2
        rts
.endp

.proc wait_blit
?w      lda VBXE_BLITTER
        bne ?w
        rts
.endp

.proc do_blit
        jsr wait_blit
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        lda bl_src
        sta MEMW+BCB_OFF+0
        lda bl_src+1
        sta MEMW+BCB_OFF+1
        lda bl_src+2
        sta MEMW+BCB_OFF+2
        lda bl_ssy
        sta MEMW+BCB_OFF+3
        lda bl_ssy+1
        sta MEMW+BCB_OFF+4
        lda bl_ssx
        sta MEMW+BCB_OFF+5
        lda bl_dst
        sta MEMW+BCB_OFF+6
        lda bl_dst+1
        sta MEMW+BCB_OFF+7
        lda bl_dst+2
        sta MEMW+BCB_OFF+8
        lda bl_dsy
        sta MEMW+BCB_OFF+9
        lda bl_dsy+1
        sta MEMW+BCB_OFF+10
        lda bl_dsx
        sta MEMW+BCB_OFF+11
        lda bl_w
        sta MEMW+BCB_OFF+12
        lda bl_w+1
        sta MEMW+BCB_OFF+13
        lda bl_h
        sta MEMW+BCB_OFF+14
        lda bl_and
        sta MEMW+BCB_OFF+15
        lda bl_xor
        sta MEMW+BCB_OFF+16
        lda #0
        sta MEMW+BCB_OFF+17     ; collision mask / zoom / pattern: unused
        sta MEMW+BCB_OFF+18
        sta MEMW+BCB_OFF+19
        lda bl_mode
        sta MEMW+BCB_OFF+20
        lda #1
        sta VBXE_BLITTER        ; go
        rts
.endp

; calc_addr: calc_out = calc_y*320 + calc_x, as a 24-bit VRAM address in bank 0.
;   y*320 = (y + y>>2)<<8 + (y&3)<<6, which needs no multiply. Preserves Y.
calc_x  dta a(0)
calc_y  dta 0
.proc calc_addr
        lda calc_y
        lsr
        lsr
        clc
        adc calc_y              ; high byte = y + y>>2
        sta ?hi
        lda calc_y
        and #3
        tax
        lda t64,x               ; low bits = (y&3)<<6
        clc
        adc calc_x
        sta calc_out
        lda ?hi
        adc calc_x+1
        sta calc_out+1
        lda #0
        sta calc_out+2
        rts
?hi     dta 0
.endp
t64     dta 0,64,128,192

.proc set_dst_calc
        lda calc_out
        sta bl_dst
        lda calc_out+1
        sta bl_dst+1
        lda calc_out+2
        sta bl_dst+2
        lda #<SCR_W
        sta bl_dsy
        lda #>SCR_W
        sta bl_dsy+1
        lda #1
        sta bl_dsx
        rts
.endp

; fill_rect: calc_x/calc_y = top-left, fr_w x fr_h, colour fr_col. Preserves Y.
fr_w    dta a(0)
fr_h    dta 0
fr_col  dta 0
.proc fill_rect
        jsr calc_addr
        jsr set_dst_calc
        lda #0                  ; a constant source: the blitter reads nothing
        sta bl_src
        sta bl_src+1
        sta bl_src+2
        sta bl_ssy
        sta bl_ssy+1
        lda #1
        sta bl_ssx
        lda fr_w
        sec
        sbc #1
        sta bl_w
        lda fr_w+1
        sbc #0
        sta bl_w+1
        lda fr_h
        sec
        sbc #1
        sta bl_h
        lda #0
        sta bl_and              ; AND=0, XOR=colour -> every output byte = colour
        lda fr_col
        sta bl_xor
        lda #0
        sta bl_mode
        jmp do_blit
.endp

; Rounded filled rectangle for the VBXE framebuffer. Three overlapping fills
; produce two stepped corner pixels, which reads as a soft 3px radius at 320x200.
rr_x    dta a(0)
rr_y    dta 0
rr_w    dta a(0)
rr_h    dta 0
rr_col  dta 0
.proc fill_round_rect
        lda calc_x
        sta rr_x
        lda calc_x+1
        sta rr_x+1
        lda calc_y
        sta rr_y
        lda fr_w
        sta rr_w
        lda fr_w+1
        sta rr_w+1
        lda fr_h
        sta rr_h
        lda fr_col
        sta rr_col

        ; Top/bottom strip: inset two pixels.
        lda rr_x
        clc
        adc #2
        sta calc_x
        lda rr_x+1
        adc #0
        sta calc_x+1
        lda rr_y
        sta calc_y
        lda rr_w
        sec
        sbc #4
        sta fr_w
        lda rr_w+1
        sbc #0
        sta fr_w+1
        lda rr_h
        sta fr_h
        lda rr_col
        sta fr_col
        jsr fill_rect

        ; Second strip: inset one pixel on every side.
        lda rr_x
        clc
        adc #1
        sta calc_x
        lda rr_x+1
        adc #0
        sta calc_x+1
        lda rr_y
        clc
        adc #1
        sta calc_y
        lda rr_w
        sec
        sbc #2
        sta fr_w
        lda rr_w+1
        sbc #0
        sta fr_w+1
        lda rr_h
        sec
        sbc #2
        sta fr_h
        jsr fill_rect

        ; Full-width centre strip.
        lda rr_x
        sta calc_x
        lda rr_x+1
        sta calc_x+1
        lda rr_y
        clc
        adc #2
        sta calc_y
        lda rr_w
        sta fr_w
        lda rr_w+1
        sta fr_w+1
        lda rr_h
        sec
        sbc #4
        sta fr_h
        jsr fill_rect

        ; Restore the caller's rectangle parameters.
        lda rr_x
        sta calc_x
        lda rr_x+1
        sta calc_x+1
        lda rr_y
        sta calc_y
        lda rr_w
        sta fr_w
        lda rr_w+1
        sta fr_w+1
        lda rr_h
        sta fr_h
        lda rr_col
        sta fr_col
        rts
.endp

;=============================================================================
; text
;=============================================================================
text_x   dta a(0)
text_y   dta 0
text_col dta 0

; draw_char: A = glyph index (ASCII-32). Source = $038000 + (gi<<6), i.e.
;   low byte (gi&3)<<6, high byte $80 + (gi>>2). Advances text_x by 8.
.proc draw_char
        sta ?gi
        lda ?gi
        and #3
        asl
        asl
        asl
        asl
        asl
        asl                     ; (gi&3) * 64
        sta bl_src
        lda ?gi
        lsr
        lsr                     ; gi>>2
        clc
        adc #FONT_HI
        sta bl_src+1
        lda #FONT_B2
        sta bl_src+2
        lda #8                  ; the sheet's rows are 8 bytes apart
        sta bl_ssy
        lda #0
        sta bl_ssy+1
        lda #1
        sta bl_ssx
        lda text_x
        sta calc_x
        lda text_x+1
        sta calc_x+1
        lda text_y
        sta calc_y
        jsr calc_addr
        jsr set_dst_calc
        lda #7                  ; 8x8 glyph
        sta bl_w
        lda #0
        sta bl_w+1
        lda #7
        sta bl_h
        lda text_col
        sta bl_and              ; 255 & colour = colour, 0 & colour = 0
        lda #0
        sta bl_xor
        lda #1
        sta bl_mode             ; transparent: an output byte of 0 leaves the pixel
        jsr do_blit
        lda text_x              ; fixed 8px advance (the game's font is proportional
        clc                     ;   and carries a width table; the ROM charset is not)
        adc #8
        sta text_x
        bcc ?nc
        inc text_x+1
?nc     rts
?gi     dta 0
.endp

; draw_text: txt_ptr -> a 0-terminated uppercase string. Anything outside 32..95
;   is skipped -- the ROM's first 64 internal codes cover exactly that range.
.proc draw_text
        ldy #0
?l      lda text_x+1            ; right-edge clip: a glyph that would run past x=319
        beq ?nclip              ;   wraps onto the next row and ghosts there
        lda text_x
        cmp #<312
        bcs ?done
?nclip  lda (txt_ptr),y
        beq ?done
        sec
        sbc #32
        bcc ?skip
        cmp #64
        bcs ?skip
        sty ?sy
        jsr draw_char
        ldy ?sy
?skip   iny
        bne ?l
?done   rts
?sy     dta 0
.endp

; text_at: A/X = string lo/hi, Y = colour. Caller sets text_x / text_y.
.proc text_at
        sta txt_ptr
        stx txt_ptr+1
        sty text_col
        jmp draw_text
.endp

;=============================================================================
; the ArrowButton widget - OpenXcom ArrowButton::draw(), transcribed.
;   Every entry below is one drawRect/setPixel call from ArrowButton.cpp, given
;   as (dx, dy, w, h, colour-offset) relative to the button's top-left. The offset
;   is added to the widget's base colour, which here is 0, so it indexes the ramp
;   directly. $FF ends a list.
;=============================================================================
awp_x     dta 0
awp_y     dta 0
awp_shape dta 0                  ; 0 = ARROW_BIG_UP, 1 = ARROW_BIG_DOWN
awp_press dta 0                  ; 1 = invert(_color+3), the held-down look

box_ops                         ; ArrowButton.cpp:99-124, the bevelled box
        dta 0,0,AW_W-1,AW_H-1,2 ; :103-108  drawRect(_color+2)
        dta 1,1,AW_W-1,AW_H-1,5 ; :110-114  drawRect(_color+5)
        dta 1,1,AW_W-2,AW_H-2,4 ; :116-120  drawRect(_color+4)
        dta 0,0,1,1,1           ; :122      setPixel(0, 0, _color+1)
        dta 0,AW_H-1,1,1,4      ; :123      setPixel(0, h-1, _color+4)
        dta AW_W-1,0,1,1,4      ; :124      setPixel(w-1, 0, _color+4)
        dta $FF
up_ops                          ; :130-152  ARROW_BIG_UP
        dta 5,8,3,3,1           ; the 3x3 stem
        dta 2,7,9,1,1           ; then the triangle, 9px wide, narrowing upward
        dta 3,6,7,1,1
        dta 4,5,5,1,1
        dta 5,4,3,1,1
        dta 6,3,1,1,1
        dta $FF
dn_ops                          ; :153-175  ARROW_BIG_DOWN
        dta 5,3,3,3,1
        dta 2,6,9,1,1
        dta 3,7,7,1,1
        dta 4,8,5,1,1
        dta 5,9,3,1,1
        dta 6,10,1,1,1
        dta $FF

; aw_col: A = colour offset (1..5) -> the palette index to draw with. Pressed is
;   Surface::invert(mid) with mid = _color+3, i.e. p -> 2*mid - p, which for
;   _color+N collapses to _color+(6-N).
.proc aw_col
        ldx awp_press
        beq ?plain
        sta ?t
        lda #6
        sec
        sbc ?t
?plain  rts
?t      dta 0
.endp

; aw_run: walk one op list, filling each rectangle at the widget's origin.
.proc aw_run
        ldy #0
?l      lda (opp),y
        cmp #$FF
        beq ?done
        clc
        adc awp_x
        sta calc_x
        lda #0
        sta calc_x+1
        iny
        lda (opp),y
        clc
        adc awp_y
        sta calc_y
        iny
        lda (opp),y
        sta fr_w
        lda #0
        sta fr_w+1
        iny
        lda (opp),y
        sta fr_h
        iny
        lda (opp),y
        sty ?sy
        jsr aw_col
        sta fr_col
        jsr fill_rect
        ldy ?sy
        iny
        jmp ?l
?done   rts
?sy     dta 0
.endp

; aw_draw: the box, then the shape. Two op lists, one walker -- exactly the
;   structure of ArrowButton::draw()'s "draw button, then switch (_shape)".
.proc aw_draw
        lda #<box_ops
        sta opp
        lda #>box_ops
        sta opp+1
        jsr aw_run
        lda awp_shape
        bne ?dn
        lda #<up_ops
        sta opp
        lda #>up_ops
        sta opp+1
        jmp aw_run
?dn     lda #<dn_ops
        sta opp
        lda #>dn_ops
        sta opp+1
        jmp aw_run
.endp

;=============================================================================
; the screen
;=============================================================================
.proc draw_screen
        lda #0                  ; clear the framebuffer
        sta calc_x
        sta calc_x+1
        sta calc_y
        sta fr_col
        lda #<SCR_W
        sta fr_w
        lda #>SCR_W
        sta fr_w+1
        lda #SCR_H
        sta fr_h
        jsr fill_rect
        lda #WIN_X              ; window: a 2px border...
        sta calc_x
        lda #0
        sta calc_x+1
        lda #WIN_Y
        sta calc_y
        lda #WIN_W&255
        sta fr_w
        lda #WIN_W/256
        sta fr_w+1
        lda #WIN_H
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect
        lda #WIN_X+2            ; ...around an inset face. (The game blits a crop of
        sta calc_x              ;   the original BACK*.SCR artwork in here instead.)
        lda #0
        sta calc_x+1
        lda #WIN_Y+2
        sta calc_y
        lda #(WIN_W-4)&255
        sta fr_w
        lda #(WIN_W-4)/256
        sta fr_w+1
        lda #WIN_H-4
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect
        jsr draw_headers
        jsr draw_rows
        jsr draw_footer
        jmp draw_crt_noise
.endp

.proc draw_headers
        lda #4
        sta text_x
        lda #0
        sta text_x+1
        lda #8
        sta text_y
        lda #<s_sys
        ldx #>s_sys
        ldy #C_HINT
        jsr text_at
        lda #32
        sta text_x
        lda #<s_status
        ldx #>s_status
        ldy #C_HINT
        jsr text_at
        lda #116
        sta text_x
        lda #<s_action
        ldx #>s_action
        ldy #C_HINT
        jsr text_at
        lda #216
        sta text_x
        lda #<s_load_head
        ldx #>s_load_head
        ldy #C_HINT
        jsr text_at
        lda #<288
        sta text_x
        lda #>288
        sta text_x+1
        lda #<s_mod_head
        ldx #>s_mod_head
        ldy #C_HINT
        jmp text_at
.endp

row_y_tab dta 18,34,50,66,82,98,114

; Fractional width tables avoid division in the frame loop. A normal cooldown
; advances through eight pixels per second; the speed upgrade uses sixteen.
frac5 dta 0,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,5
frac3 dta 0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
frac10 dta 0,1,1,1,1,1,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,5,5,6,6,7,7,7,7,7,8,8,8,8,8,9,9,9,9,9,10,10,10,10,10,10,10,10
frac20 dta 0,1,1,2,2,2,3,3,4,4,4,5,5,6,6,6,7,7,8,8,8,9,9,10,10,10,11,11,12,12,12,13,13,14,14,14,15,15,16,16,16,17,17,18,18,18,19,19,20,20,20

.proc get_progress_width       ; X=system, A=remaining width (0..80)
        lda cooldown,x
        beq ?zero
        sec
        sbc #1
        ldy cooldown_full,x
        cpy #5
        beq ?fast
        sta ?base
        asl
        asl
        clc
        adc ?base               ; seconds * 5
        asl                     ; seconds * 10
        sta ?base
        ldy cooldown_frac,x
        lda frac10,y
        clc
        adc ?base
        rts
?fast   sta ?base
        asl
        asl
        clc
        adc ?base               ; seconds * 5
        asl
        asl                     ; seconds * 20
        sta ?base
        ldy cooldown_frac,x
        lda frac20,y
        clc
        adc ?base
        rts
?zero   lda #0
        rts
?base   dta 0
.endp

.proc get_special_width        ; X=system, 20 seconds -> 100 pixels
        lda special_sec,x
        beq ?zero
        sec
        sbc #1
        sta ?base
        asl
        asl
        clc
        adc ?base               ; seconds * 5
        sta ?base
        ldy special_frac,x
        lda frac5,y
        clc
        adc ?base
        rts
?zero   lda #0
        rts
?base   dta 0
.endp

; Redraw only the narrow progress strips each frame. This mirrors the original
; browser game, where timer/cooldown controls the overlay width continuously.
.proc draw_progress
        ldx #0
?row    stx ?idx
        lda #112
        sta calc_x
        lda #0
        sta calc_x+1
        lda row_y_tab,x
        clc
        adc #11
        sta calc_y
        lda #100
        sta fr_w
        lda #0
        sta fr_w+1
        lda #2
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
        ldx ?idx
        lda special_sec,x
        beq ?normal_progress
        jsr get_special_width
        jmp ?progress
?normal_progress
        jsr get_progress_width
?progress
        beq ?next
        sta fr_w
        lda #C_COOLDOWN
        sta fr_col
        jsr fill_rect
?next   ldx ?idx
        lda system_load_pwr,x
        ora system_load_lif,x
        beq ?advance
        lda #212
        sta calc_x
        lda #0
        sta calc_x+1
        lda row_y_tab,x
        clc
        adc #11
        sta calc_y
        lda #60
        sta fr_w
        lda #0
        sta fr_w+1
        lda #2
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
        lda load_sec
        beq ?advance
        sec
        sbc #1
        sta ?seconds
        asl
        clc
        adc ?seconds            ; (seconds-1) * 3
        sta ?loadw
        lda #50
        sec
        sbc frame50
        tay
        lda frac3,y
        clc
        adc ?loadw
        beq ?advance
        sta fr_w
        lda #C_LOADPROG
        sta fr_col
        jsr fill_rect
?advance ldx ?idx
        inx
        cpx #7
        beq ?done
        jmp ?row
?done   rts
?idx    dta 0
?seconds dta 0
?loadw  dta 0
.endp

icon_draw_idx dta 0
icon_draw_x dta a(12)
icon_draw_y dta 0
.proc draw_icon               ; X=system index
        stx icon_draw_idx
        txa
        and #3
        asl
        asl
        asl
        asl
        asl
        asl
        sta bl_src
        txa
        lsr
        lsr
        clc
        adc #ICON_HI
        sta bl_src+1
        lda #ICON_B2
        sta bl_src+2
        lda #8
        sta bl_ssy
        lda #0
        sta bl_ssy+1
        lda #1
        sta bl_ssx
        lda icon_draw_x
        sta calc_x
        lda icon_draw_x+1
        sta calc_x+1
        lda icon_draw_y
        sta calc_y
        jsr calc_addr
        jsr set_dst_calc
        lda #7
        sta bl_w
        lda #0
        sta bl_w+1
        lda #7
        sta bl_h
        lda #255
        sta bl_and
        lda #0
        sta bl_xor
        lda #1
        sta bl_mode
        jmp do_blit
.endp

status_idx dta 0
status_cell dta 0
status_x dta 0
status_col dta 0
.proc draw_status_boxes       ; X=system, status_col already selected
        stx status_idx
        lda #0
        sta status_cell
        lda #BAR_X
        sta status_x
?cell  lda status_x
        sta calc_x
        lda #0
        sta calc_x+1
        ldx status_idx
        lda row_y_tab,x
        clc
        adc #4
        sta calc_y
        lda #7
        sta fr_w
        lda #0
        sta fr_w+1
        lda #6
        sta fr_h
        ldy status_idx
        lda status_cell
        cmp health,y
        bcs ?empty
        lda status_col
        sta fr_col
        jsr fill_round_rect
        jmp ?next
?empty  lda #C_TEXT
        sta fr_col
        jsr fill_round_rect
        inc calc_x
        inc calc_y
        lda #5
        sta fr_w
        lda #4
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
?next   inc status_cell
        lda status_x
        clc
        adc #8
        sta status_x
        lda status_cell
        cmp #10
        bne ?cell
        rts
.endp

price_x dta 0
price_y dta 0
price_idx dta 0
term_amount dta 0
term_icon dta 0
term_sign dta 0
.proc draw_price_term          ; A=amount, X=icon, Y=sign glyph (+11 / -13)
        sta term_amount
        stx term_icon
        sty term_sign
        lda price_x
        sta text_x
        lda #0
        sta text_x+1
        lda price_y
        sta text_y
        lda #C_ONLINE
        cpy #11
        beq ?colour
        lda #C_OFFLINE
?colour sta text_col
        lda term_sign
        jsr draw_char
        lda term_amount
        clc
        adc #16                 ; one decimal digit
        jsr draw_char
        lda price_x
        clc
        adc #16
        sta icon_draw_x
        lda price_y
        sta icon_draw_y
        ldx term_icon
        jsr draw_icon
        lda price_x
        clc
        adc #24
        sta price_x
        rts
.endp

.proc draw_action_price        ; X=action/system index
        stx price_idx
        lda #116
        sta price_x
        lda row_y_tab,x
        clc
        adc #3
        sta price_y
        lda gain_tab,x
        ldy #11                 ; '+'
        jsr draw_price_term
        ldx price_idx
        lda cost_pwr,x
        beq ?life
        ldx #0
        ldy #13                 ; '-'
        jsr draw_price_term
?life   ldx price_idx
        lda cost_lif,x
        beq ?processing
        ldx #1
        ldy #13
        jsr draw_price_term
?processing
        ldx price_idx
        lda cost_prc,x
        beq ?done
        ldx #2
        ldy #13
        jsr draw_price_term
?done   rts
.endp

.proc draw_system_load         ; X=system index, recurring deductions only
        stx price_idx
        lda #216
        sta price_x
        lda row_y_tab,x
        clc
        adc #3
        sta price_y
        lda system_load_pwr,x
        beq ?life
        ldx #0
        ldy #13
        jsr draw_price_term
?life   ldx price_idx
        lda system_load_lif,x
        beq ?done
        ldx #1
        ldy #13
        jsr draw_price_term
?done   rts
.endp

lm_idx dta 0
.proc draw_load_modification  ; X=system index
        stx lm_idx
        jsr draw_system_load
        ldx lm_idx
        cpx #3
        bcs ?high
        jmp ?done
?high
        cpx #6
        bcc ?mod_draw
        jmp ?done
?mod_draw
        lda #<288
        sta text_x
        lda #>288
        sta text_x+1
        lda row_y_tab,x
        clc
        adc #3
        sta text_y
        txa
        sec
        sbc #2
        sta ?type
        jsr modification_available
        bcc ?done
        lda ?type
        cmp #1
        bne ?auto_mod
        lda #<s_amount
        ldx #>s_amount
        bne ?colour
?auto_mod cmp #2
        bne ?speed_mod
        lda #<s_auto
        ldx #>s_auto
        bne ?colour
?speed_mod
        lda #<s_speed
        ldx #>s_speed
?colour ldy #C_VALUE
?print  jsr text_at
?done   rts
?type   dta 0
.endp

action_key_glyph dta 48,44,47,37,39,46,51 ; P,L,O,E,G,N,S (ASCII-32)
resource_key_glyph dta 48,44,47             ; P,L,O
.proc draw_special_name        ; X=main system
        stx ?system
        lda #116
        sta text_x
        lda #0
        sta text_x+1
        lda row_y_tab,x
        clc
        adc #3
        sta text_y
        cpx #3
        bne ?guidance
        lda #<s_install
        ldx #>s_install
        bne ?print
?guidance cpx #4
        bne ?engines
        lda #<s_plot
        ldx #>s_plot
        bne ?print
?engines cpx #5
        bne ?sensors
        lda #<s_jump
        ldx #>s_jump
        bne ?print
?sensors lda #<s_scan
        ldx #>s_scan
?print  ldy #C_VALUE
        jmp text_at
?system dta 0
.endp
.proc draw_rows
        ; Include the shortcut glyph cell (x=8..15) in the redraw.  The row
        ; face starts at x=12, so clearing from ROW_X used to leave the left
        ; half of a shortcut behind after an action entered cooldown/locked.
        lda #8
        sta calc_x
        lda #0
        sta calc_x+1
        lda #16
        sta calc_y
        lda #300&255
        sta fr_w
        lda #300/256
        sta fr_w+1
        lda #114
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
        ldx #0
?row    stx ?idx
        ldx ?idx
        jsr action_active
        bcc ?icon
        lda #8
        sta text_x
        lda #0
        sta text_x+1
        lda row_y_tab,x
        clc
        adc #3
        sta text_y
        lda #C_VALUE
        sta text_col
        lda action_key_glyph,x
        jsr draw_char
?icon
        lda #20
        sta icon_draw_x
        ldx ?idx
        lda row_y_tab,x
        clc
        adc #3
        sta icon_draw_y
        ldx ?idx
        jsr draw_icon

        ; Ten discrete condition boxes, matching the original browser game.
        ldx ?idx
        lda health,x
        cmp #4
        bcc ?off
        cmp #8
        bcc ?deg
        lda #C_ONLINE
        bne ?boxes
?deg    lda #C_DEGRADE
        bne ?boxes
?off    lda #C_OFFLINE
?boxes  sta status_col
        jsr draw_status_boxes

        ldx ?idx
        lda special_available,x
        beq ?normal_action
        jsr draw_special_name
        jmp ?load
?normal_action
        lda unlocked,x
        beq ?load
        cpx #3
        bcc ?price
        lda clicks,x
        cmp #3
        bcs ?load
?price
        jsr draw_action_price
?load
        ldx ?idx
        jsr draw_load_modification
        ldx ?idx
        inx
        cpx #7
        beq ?done
        jmp ?row
?done
        rts
?idx    dta 0
.endp

.proc draw_2digit              ; A=0..99, at text cursor
        ldx #0
?t      cmp #10
        bcc ?ones
        sec
        sbc #10
        inx
        bne ?t
?ones   sta ?u
        txa
        clc
        adc #16
        jsr draw_char
        lda ?u
        clc
        adc #16
        jmp draw_char
?u      dta 0
.endp

legend_x dta 0
legend_y dta 0
legend_icon dta 0
.proc draw_legend_item         ; A/X=label, Y=system icon
        sta txt_ptr
        stx txt_ptr+1
        sty legend_icon
        lda legend_x
        sta icon_draw_x
        lda legend_y
        sta icon_draw_y
        ldx legend_icon
        jsr draw_icon
        lda legend_x
        clc
        adc #12
        sta text_x
        lda #0
        sta text_x+1
        lda legend_y
        sta text_y
        lda #C_TEXT
        sta text_col
        jmp draw_text
.endp

; Compact 3x5 uppercase font and 4x4 icons used only by the one-line legend.
; Each font byte contains one three-pixel row in bits 2..0.
tiny_font
        dta 2,5,7,5,5, 6,5,6,5,6, 3,4,4,4,3, 6,5,5,5,6
        dta 7,4,6,4,7, 7,4,6,4,4, 3,4,5,5,3, 5,5,7,5,5
        dta 7,2,2,2,7, 1,1,1,5,2, 5,5,6,5,5, 4,4,4,4,7
        dta 5,7,7,5,5, 5,7,7,7,5, 2,5,5,5,2, 6,5,6,4,4
        dta 2,5,5,3,1, 6,5,6,5,5, 3,4,2,1,6, 7,2,2,2,2
        dta 5,5,5,5,7, 5,5,5,5,2, 5,5,7,7,5, 5,5,2,5,5
        dta 5,5,2,2,2, 7,1,2,4,7
tiny_icon_bits
        dta 2,6,3,2              ; power
        dta 10,15,14,4           ; life support
        dta 15,9,11,15           ; processing
        dta 9,6,6,9              ; engineering
        dta 6,15,11,15           ; guidance
        dta 6,15,10,5            ; engines
        dta 1,10,6,4             ; sensors
tiny_masks dta 4,2,1
tiny_icon_masks dta 8,4,2,1
tiny_x dta a(0)
tiny_y dta 0
tiny_glyph dta 0
tiny_row dta 0
tiny_col dta 0
tiny_bits dta 0
tiny_string_y dta 0
tiny_colour dta C_TEXT

.proc draw_tiny_pixel
        lda tiny_x
        clc
        adc tiny_col
        sta calc_x
        lda tiny_x+1
        adc #0
        sta calc_x+1
        lda tiny_y
        clc
        adc tiny_row
        sta calc_y
        lda #1
        sta fr_w
        lda #0
        sta fr_w+1
        lda #1
        sta fr_h
        lda tiny_colour
        sta fr_col
        jmp fill_rect
.endp

.proc advance_tiny_x
        lda tiny_x
        clc
        adc #4
        sta tiny_x
        bcc ?done
        inc tiny_x+1
?done   rts
.endp

.proc draw_tiny_char           ; A=letter index 0..25
        sta tiny_glyph
        asl
        asl
        clc
        adc tiny_glyph          ; glyph * 5
        tax
        lda #0
        sta tiny_row
?row   lda tiny_font,x
        sta tiny_bits
        stx ?font_x
        lda #0
        sta tiny_col
?col   ldy tiny_col
        lda tiny_masks,y
        and tiny_bits
        beq ?next
        jsr draw_tiny_pixel
?next  inc tiny_col
        lda tiny_col
        cmp #3
        bne ?col
        ldx ?font_x
        inx
        inc tiny_row
        lda tiny_row
        cmp #5
        bne ?row
        jmp advance_tiny_x
?font_x dta 0
.endp

.proc draw_tiny_text           ; A/X=zero-terminated uppercase label
        sta txt_ptr
        stx txt_ptr+1
        lda #C_TEXT
        sta tiny_colour
        ldy #0
?char  lda (txt_ptr),y
        beq ?done
        sty tiny_string_y
        cmp #32
        beq ?space
        sec
        sbc #65
        bcc ?space
        cmp #26
        bcs ?space
        jsr draw_tiny_char
        jmp ?next
?space jsr advance_tiny_x
?next  ldy tiny_string_y
        iny
        bne ?char
?done  rts
.endp

.proc draw_tiny_icon           ; X=system index, tiny_x/tiny_y=position
        lda icon_cols,x
        sta tiny_colour
        txa
        asl
        asl
        tax
        lda #0
        sta tiny_row
?row   lda tiny_icon_bits,x
        sta tiny_bits
        stx ?icon_x
        lda #0
        sta tiny_col
?col   ldy tiny_col
        lda tiny_icon_masks,y
        and tiny_bits
        beq ?next
        jsr draw_tiny_pixel
?next  inc tiny_col
        lda tiny_col
        cmp #4
        bne ?col
        ldx ?icon_x
        inx
        inc tiny_row
        lda tiny_row
        cmp #4
        bne ?row
        rts
?icon_x dta 0
.endp

.proc draw_tiny_legend_item    ; A/X=label, Y=system, tiny_x=icon position
        sta ?label
        stx ?label+1
        sty ?system
        lda tiny_x
        sta icon_draw_x
        lda tiny_x+1
        sta icon_draw_x+1
        lda tiny_y
        sec
        sbc #2
        sta icon_draw_y
        tya
        tax
        jsr draw_icon
        lda #0
        sta icon_draw_x+1       ; normal game icons use the first 256 pixels
        lda tiny_x
        clc
        adc #8
        sta tiny_x
        bcc ?label_ready
        inc tiny_x+1
?label_ready
        lda ?label
        ldx ?label+1
        jmp draw_tiny_text
?label dta a(0)
?system dta 0
.endp

.proc draw_footer
        lda #HINT_X
        sta calc_x
        sta text_x
        lda #0
        sta calc_x+1
        sta text_x+1
        lda #148
        sta calc_y
        lda #296&255
        sta fr_w
        lda #296/256
        sta fr_w+1
        lda #47
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
        lda #12
        sta tiny_x
        lda #0
        sta tiny_x+1
        lda #189
        sta tiny_y
        lda #<s_power
        ldx #>s_power
        ldy #0
        jsr draw_tiny_legend_item
        lda #40
        sta tiny_x
        lda #<s_life
        ldx #>s_life
        ldy #1
        jsr draw_tiny_legend_item
        lda #96
        sta tiny_x
        lda #<s_process
        ldx #>s_process
        ldy #2
        jsr draw_tiny_legend_item
        lda #144
        sta tiny_x
        lda #<s_engineer
        ldx #>s_engineer
        ldy #3
        jsr draw_tiny_legend_item
        lda #196
        sta tiny_x
        lda #<s_guidance
        ldx #>s_guidance
        ldy #4
        jsr draw_tiny_legend_item
        lda #236
        sta tiny_x
        lda #<s_engines
        ldx #>s_engines
        ldy #5
        jsr draw_tiny_legend_item
        lda #16
        sta tiny_x
        lda #1
        sta tiny_x+1
        lda #<s_sensors
        ldx #>s_sensors
        ldy #6
        jmp draw_tiny_legend_item
.endp

; A fixed, sparse phosphor pattern keeps the interface legible while breaking up
; the perfectly flat framebuffer. Points sit mainly in the gaps between rows.
noise_idx dta 0
.proc draw_crt_noise
        lda #2
        sta fr_w
        lda #0
        sta fr_w+1
        lda #1
        sta fr_h
        lda #C_NOISE
        sta fr_col
        lda #0
        sta noise_idx
?point ldx noise_idx
        lda crt_noise_points+2,x
        cmp #$FF
        beq ?done
        sta calc_y
        lda crt_noise_points,x
        sta calc_x
        lda crt_noise_points+1,x
        sta calc_x+1
        jsr fill_rect
        lda noise_idx
        clc
        adc #3
        sta noise_idx
        bne ?point
?done   rts
.endp

crt_noise_points
        dta a(16),17,  a(74),17,  a(158),17, a(242),17, a(304),17
        dta a(58),31,  a(137),31, a(263),31
        dta a(18),47,  a(186),47, a(302),47
        dta a(92),63,  a(230),63
        dta a(44),79,  a(169),79, a(276),79
        dta a(121),95, a(248),95
        dta a(67),111, a(193),111, a(304),127
        dta a(35),137, a(152),142, a(282),133
        dta a(20),173, a(103),181, a(251),177, a(300),184
        dta 0,0,$FF

.proc draw_denied
        lda #HINT_X
        sta text_x
        lda #0
        sta text_x+1
        lda #176
        sta text_y
        lda #<s_denied
        ldx #>s_denied
        ldy #C_OFFLINE
        jmp text_at
.endp

.proc draw_end
        lda #28
        sta calc_x
        lda #0
        sta calc_x+1
        lda #54
        sta calc_y
        lda #264&255
        sta fr_w
        lda #264/256
        sta fr_w+1
        lda #94
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect
        lda #30
        sta calc_x
        lda #56
        sta calc_y
        lda #260&255
        sta fr_w
        lda #260/256
        sta fr_w+1
        lda #90
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect
        lda #48
        sta text_x
        lda #0
        sta text_x+1
        lda #68
        sta text_y
        lda game_mode
        cmp #1
        bne ?lost
        lda #<s_win_title
        ldx #>s_win_title
        ldy #C_ONLINE
        jsr text_at
        lda #48
        sta text_x
        lda #84
        sta text_y
        lda #<s_win_line1
        ldx #>s_win_line1
        ldy #C_TEXT
        jsr text_at
        lda #48
        sta text_x
        lda #96
        sta text_y
        lda #<s_win_line2
        ldx #>s_win_line2
        ldy #C_TEXT
        jsr text_at
        jmp ?restart
?lost   ldx failure_system
        cpx #0
        bne ?life
        lda #<s_power_fail
        ldx #>s_power_fail
        bne ?fail_title
?life   cpx #1
        bne ?processing
        lda #<s_life_fail
        ldx #>s_life_fail
        bne ?fail_title
?processing
        lda #<s_processing_fail
        ldx #>s_processing_fail
?fail_title ldy #C_OFFLINE
        jsr text_at
        lda #48
        sta text_x
        lda #84
        sta text_y
        lda failure_system
        cmp #0
        bne ?life_lines
        lda #<s_power_line1
        ldx #>s_power_line1
        jsr ?line1
        lda #<s_power_line2
        ldx #>s_power_line2
        bne ?line2
?life_lines cmp #1
        bne ?process_lines
        lda #<s_life_line1
        ldx #>s_life_line1
        jsr ?line1
        lda #<s_life_line2
        ldx #>s_life_line2
        bne ?line2
?process_lines
        lda #<s_process_line1
        ldx #>s_process_line1
        jsr ?line1
        lda #<s_process_line2
        ldx #>s_process_line2
?line2  ldy #C_TEXT
        jsr text_at
        jmp ?restart
?line1  ldy #C_TEXT
        jsr text_at
        lda #48
        sta text_x
        lda #96
        sta text_y
        rts
?restart
        lda #76
        sta text_x
        lda #0
        sta text_x+1
        lda #126
        sta text_y
        lda #<s_restart
        ldx #>s_restart
        ldy #C_HINT
        jmp text_at
.endp

.proc draw_story_modal
        jsr draw_end_box
        lda #48
        sta text_x
        lda #0
        sta text_x+1
        lda #68
        sta text_y
        ldx story_type
        cpx #7
        bne ?guidance
        lda #<s_scan_title
        ldx #>s_scan_title
        bne ?title
?guidance cpx #5
        bne ?engines
        lda #<s_plot_title
        ldx #>s_plot_title
        bne ?title
?engines cpx #6
        bne ?engineering
        lda #<s_jump_title
        ldx #>s_jump_title
        bne ?title
?engineering
        lda #<s_source_title
        ldx #>s_source_title
?title  ldy #C_TITLE
        jsr text_at
        lda #48
        sta text_x
        lda #86
        sta text_y
        lda #<s_story_line1
        ldx #>s_story_line1
        ldy #C_TEXT
        jsr text_at
        lda #48
        sta text_x
        lda #98
        sta text_y
        lda #<s_story_line2
        ldx #>s_story_line2
        ldy #C_TEXT
        jsr text_at
        lda #168
        sta text_x
        lda #126
        sta text_y
        lda #<s_continue
        ldx #>s_continue
        ldy #C_HINT
        jmp text_at
.endp

.proc draw_end_box
        lda #28
        sta calc_x
        lda #0
        sta calc_x+1
        lda #54
        sta calc_y
        lda #264&255
        sta fr_w
        lda #264/256
        sta fr_w+1
        lda #94
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect
        lda #30
        sta calc_x
        lda #56
        sta calc_y
        lda #260&255
        sta fr_w
        lda #260/256
        sta fr_w+1
        lda #90
        sta fr_h
        lda #C_WIN
        sta fr_col
        jmp fill_round_rect
.endp

modal_idx dta 0
modal_y dta 0
modal_mask dta 0
.proc draw_modification_modal
        lda #20
        sta calc_x
        lda #0
        sta calc_x+1
        lda #32
        sta calc_y
        lda #280&255
        sta fr_w
        lda #280/256
        sta fr_w+1
        lda #136
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect
        lda #22
        sta calc_x
        lda #34
        sta calc_y
        lda #276&255
        sta fr_w
        lda #276/256
        sta fr_w+1
        lda #132
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect
        lda #36
        sta text_x
        lda #0
        sta text_x+1
        lda #42
        sta text_y
        lda modal_type
        cmp #1
        bne ?auto_title
        lda #<s_amount_title
        ldx #>s_amount_title
        lda amount_mask
        sta modal_mask
        lda #<s_amount_title
        ldx #>s_amount_title
        bne ?title
?auto_title cmp #2
        bne ?speed_title
        lda auto_mask
        sta modal_mask
        lda #<s_auto_title
        ldx #>s_auto_title
        bne ?title
?speed_title
        lda speed_mask
        sta modal_mask
        lda #<s_speed_title
        ldx #>s_speed_title
?title  ldy #C_TITLE
        jsr text_at
        lda #36
        sta text_x
        lda #0
        sta text_x+1
        lda #53
        sta text_y
        lda modal_type
        cmp #1
        bne ?auto_desc
        lda #<s_amount_desc
        ldx #>s_amount_desc
        bne ?desc
?auto_desc cmp #2
        bne ?speed_desc
        lda #<s_auto_desc
        ldx #>s_auto_desc
        bne ?desc
?speed_desc
        lda #<s_speed_desc
        ldx #>s_speed_desc
?desc   ldy #C_HINT
        jsr text_at
        lda #0
        sta modal_idx
        lda #70
        sta modal_y
?option ldx modal_idx
        lda bit_tab,x
        and modal_mask
        sta ?installed
        lda #32
        sta calc_x
        lda #0
        sta calc_x+1
        lda modal_y
        sec
        sbc #2
        sta calc_y
        lda #256&255
        sta fr_w
        lda #256/256
        sta fr_w+1
        lda #22
        sta fr_h
        lda #C_SELECT
        ldy ?installed
        beq ?face
        lda #C_BORDER
?face   sta fr_col
        jsr fill_round_rect
        lda ?installed
        bne ?icon
        lda #40
        sta text_x
        lda #0
        sta text_x+1
        lda modal_y
        sta text_y
        lda #C_VALUE
        sta text_col
        ldx modal_idx
        lda resource_key_glyph,x
        jsr draw_char
?icon   lda #56
        sta icon_draw_x
        lda modal_y
        sta icon_draw_y
        ldx modal_idx
        jsr draw_icon
        lda #70
        sta text_x
        lda #0
        sta text_x+1
        lda modal_y
        sta text_y
        ldx modal_idx
        lda names_lo,x
        sta txt_ptr
        lda names_hi,x
        sta txt_ptr+1
        lda #C_TEXT
        sta text_col
        jsr draw_text
        lda ?installed
        beq ?active_detail
        lda #<210
        sta text_x
        lda #>210
        sta text_x+1
        lda modal_y
        sta text_y
        lda #<s_installed
        ldx #>s_installed
        ldy #C_ONLINE
        jsr text_at
        lda #C_HINT
        bne ?detail
?active_detail
        lda #C_TEXT
?detail sta modal_detail_col
        jsr draw_modification_detail
?next   inc modal_idx
        lda modal_y
        clc
        adc #24
        sta modal_y
        lda modal_idx
        cmp #3
        beq ?options_done
        jmp ?option
?options_done
        lda #204
        sta text_x
        lda #0
        sta text_x+1
        lda #150
        sta text_y
        lda #<s_cancel
        ldx #>s_cancel
        ldy #C_HINT
        jmp text_at
?installed dta 0
.endp

modal_detail_col dta 0
.proc draw_modification_detail
        lda modal_type
        cmp #1
        bne ?auto
        jmp draw_amount_modification_detail
?auto   cmp #2
        bne ?speed
        lda #<s_auto_detail
        ldx #>s_auto_detail
        bne ?print
?speed  lda #<s_speed_detail
        ldx #>s_speed_detail
?print  pha
        lda #70
        sta text_x
        lda #0
        sta text_x+1
        lda modal_y
        clc
        adc #10
        sta text_y
        pla
        ldy modal_detail_col
        jmp text_at
.endp

amount_old_gain dta 2,1,3
amount_cost_icon dta 2,0,0
amount_old_cost dta 1,1,1
amount_new_gain dta 5,3,7
amount_new_cost dta 2,1,2
.proc draw_amount_modification_detail
        lda #70
        sta price_x
        lda modal_y
        clc
        adc #10
        sta price_y

        ldx modal_idx
        lda amount_old_gain,x
        ldy #11                 ; '+'
        jsr draw_price_term
        ldx modal_idx
        lda amount_old_cost,x
        pha
        lda amount_cost_icon,x
        tax
        pla
        ldy #13                 ; '-'
        jsr draw_price_term

        lda #120
        sta text_x
        lda #0
        sta text_x+1
        lda price_y
        sta text_y
        lda modal_detail_col
        sta text_col
        lda #30                 ; '>'
        jsr draw_char

        lda #132
        sta price_x
        ldx modal_idx
        lda amount_new_gain,x
        ldy #11
        jsr draw_price_term
        ldx modal_idx
        lda amount_new_cost,x
        pha
        lda amount_cost_icon,x
        tax
        pla
        ldy #13
        jmp draw_price_term
.endp

s_power    dta c'POWER',0
s_life     dta c'LIFE SUPPORT',0
s_process  dta c'PROCESSING',0
s_engineer dta c'ENGINEERING',0
s_guidance dta c'GUIDANCE',0
s_engines  dta c'ENGINES',0
s_sensors  dta c'SENSORS',0
s_sys      dta c'KEY',0
s_status   dta c'STATUS',0
s_action   dta c'ACTION',0
s_load_head dta c'LOAD',0
s_mod_head dta c'M',0
s_ready    dta c'READY',0
s_wait     dta c'WAIT',0
s_locked   dta c'LOCK',0
s_none     dta c'--',0
s_amount   dta c'A',0
s_amount_on dta c'A',0
s_auto     dta c'U',0
s_auto_on  dta c'U',0
s_speed    dta c'D',0
s_speed_on dta c'D',0
s_install  dta c'INSTALL',0
s_plot     dta c'PLOT',0
s_jump     dta c'JUMP',0
s_scan     dta c'SCAN',0
s_amount_title dta c'AMOUNT MODIFICATION',0
s_auto_title dta c'AUTO MODIFICATION',0
s_speed_title dta c'SPEED MODIFICATION',0
s_amount_desc dta c'IMPROVES ONE RESOURCE ACTION',0
s_auto_desc dta c'RUNS ONE RESOURCE AUTOMATICALLY',0
s_speed_desc dta c'HALVES ONE RESOURCE COOLDOWN',0
s_auto_detail dta c'MANUAL > AUTO EVERY COOLDOWN',0
s_speed_detail dta c'10 SEC COOLDOWN > 5 SEC',0
s_installed dta c'INSTALLED',0
s_cancel   dta c'ESC CANCEL',0
s_scan_title dta c'SECTOR SCAN COMPLETE',0
s_plot_title dta c'COURSE PLOTTED',0
s_jump_title dta c'JUMPDRIVE ACTIVATED',0
s_source_title dta c'SOURCE INSTALLED',0
s_story_line1 dta c'OPERATION COMPLETED SUCCESSFULLY.',0
s_story_line2 dta c'THE NEXT SHIP ACTION IS READY.',0
s_continue dta c'ENTER CONTINUE',0
s_win_title dta c'ALL MAIN SYSTEMS ONLINE',0
s_win_line1 dta c'JUMP COURSE TO THE NEAREST',0
s_win_line2 dta c'SPACEPORT IS READY. YOU WIN!',0
s_power_fail dta c'POWER SYSTEM FAILURE',0
s_power_line1 dta c'THE LIGHTS FAIL. AIR STALES.',0
s_power_line2 dta c'THE CREW FALLS SILENT.',0
s_life_fail dta c'LIFE SUPPORT FAILURE',0
s_life_line1 dta c'THE AIR TURNS STALE.',0
s_life_line2 dta c'THE CREW DRIFTS TO SLEEP.',0
s_processing_fail dta c'PROCESSING FAILURE',0
s_process_line1 dta c'POWER CONTROL COLLAPSES.',0
s_process_line2 dta c'FIRE CONSUMES THE SHIP.',0
s_denied   dta c'ACTION LOCKED, COOLING, OR TOO COSTLY',0
s_won      dta c'ALL MAIN SYSTEMS ONLINE!',0
s_lost     dta c'A SHIP SYSTEM WAS DESTROYED.',0
s_restart  dta c'PRESS FIRE TO RESTART',0

        run main
