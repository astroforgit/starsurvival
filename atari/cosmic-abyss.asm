;=============================================================================
; cosmic-abyss.asm - self-contained VBXE survival game. Assemble with MADS:
;
;       mads atari/cosmic-abyss.asm -o:atari/cosmic-abyss.xex
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
;      built at runtime from a custom condensed 5x7 terminal face (see font_expand):
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
; Needs a VBXE. Without one it just flashes the border and stops.
;=============================================================================

; ---- Atari OS / hardware ----
SDMCTL   = $022F                ; OS shadow of DMACTL; the VBI copies it every frame
COLOR4   = $02C8
CH       = $02FC                ; OS keyboard scan-code shadow, $FF = no key
RTCLOK   = $12                  ; three-byte OS frame clock; RTCLOK+2 changes fastest
PORTA    = $D300                ; controller port 0 direction bits (0 = pushed)
PORTB    = $D301                ; XL/XE memory control; bit 1 exposes RAM under BASIC
STRIG0   = $D010
DMACTL   = $D400
VCOUNT   = $D40B

; ---- VBXE ----
; These addresses are assembled for the $D6 register page. detect_vbxe patches
; the high byte of every runtime access to $D7 when that is where the core is
; found, allowing the same XEX to run with either standard VBXE mapping.
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
ICON_BANK = $39                 ; eight coloured 8x8 system icons at $039000
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
C_NOISE   = 26                  ; faint phosphor grain; icon colours stay 18..25

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
        lda PORTB
        ora #2                  ; expose RAM under BASIC before VBXE relocation;
        sta PORTB               ; two patched drawing instructions live there
        jsr detect_vbxe
        bcs ?ok
        lda #$34                ; no VBXE -> red border, park
        sta COLOR4
        jmp *
?ok     lda #0
        sta SDMCTL              ; ANTIC playfield off. Setting the SHADOW is what
        sta DMACTL              ;   makes it stick: the OS VBI reloads DMACTL from it.
        lda #$90+MC_CPU         ; MEMAC-A: map a 4K VRAM window at $9000, CPU side
vbreg_main_memac
        sta VBXE_MEMAC_CTRL
        lda #0
vbreg_main_vctl
        sta VBXE_VCTL
        jsr setup_xdl
        jsr blit_init
        jsr load_pal
        jsr font_expand
        jsr icons_expand
        jsr enable_display
        jsr draw_title_screen
        jsr wait_title_input
        jsr draw_briefing_screen
        lda brief_skipped
        bne ?begin_game
        jsr wait_continue_input
?begin_game
        jsr game_init
        jsr draw_screen
        jmp loop
.endp

;=============================================================================
; loop - one pass per PAL/NTSC frame. Input is edge-triggered; timers and the
; recurring ship load continue in real time.
;=============================================================================
selected dta 0
difficulty dta 0                ; 0 Normal, 1 Easy, 2 Very Easy
old_stick dta 15
old_fire dta 1
frame50  dta 0
load_sec dta 20
load_interval dta 20
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
radioactive dta 0               ; inverse resource: zero is safe, ten is maximum
relax_sec dta 0
relax_done dta 0
relax_release dta 0

; Per-action immediate deltas. Positive values repair the selected system;
; costs are subtracted explicitly in perform_action.
gain_tab dta 2,1,3,2,2,3,2
cost_pwr dta 0,1,1,2,1,3,1
cost_lif dta 0,0,0,0,0,1,0
cost_prc dta 1,0,0,2,0,0,1
bit_tab  dta 1,2,4,8,16,32,64

; Seven entries per difficulty: Normal, Easy, Very Easy.
difficulty_health
        dta 2,7,9,2,2,1,3, 3,8,10,2,2,1,3, 5,9,10,3,3,2,4
difficulty_gain
        dta 2,1,3,2,2,3,2, 3,2,4,2,2,3,2, 4,3,5,3,3,4,3
difficulty_cost_pwr
        dta 0,1,1,2,1,3,1, 0,1,1,1,1,2,1, 0,0,1,1,0,1,0
difficulty_cost_lif
        dta 0,0,0,0,0,1,0, 0,0,0,0,0,1,0, 0,0,0,0,0,0,0
difficulty_cost_prc
        dta 1,0,0,2,0,0,1, 1,0,0,1,0,0,0, 0,0,0,1,0,0,0
difficulty_initial_load dta 4,6,8
difficulty_load_interval dta 20,24,30

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
        lda CH
        and #$3F
        cmp #$21                ; Space
        beq ?restart_now
        lda STRIG0
        cmp old_fire
        beq ?store
        cmp #0
        bne ?store
?restart_now
        lda #$FF
        sta CH
        jsr game_init
        jsr draw_screen
?store  lda STRIG0
        sta old_fire
        jmp loop
.endp

.proc game_init
        ldx #6
?copy   lda #0
        sta health,x
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
        sta radioactive
        sta relax_done
        sta relax_release
        sta old_stick
        jsr init_events
        lda #$FF
        sta failure_system
        ldx difficulty
        lda difficulty_initial_load,x
        sta load_sec
        lda difficulty_load_interval,x
        sta load_interval
        lda RTCLOK+2            ; choose 60..120 seconds from the live OS clock
        eor RTCLOK+1
        eor VCOUNT
?relax_random
        cmp #61
        bcc ?relax_ready
        sec
        sbc #61
        bcs ?relax_random
?relax_ready
        clc
        adc #60
        sta relax_sec
        lda difficulty
        sta ?preset_offset
        asl
        asl
        asl
        sec
        sbc ?preset_offset      ; difficulty * 7
        tay
        ldx #0
?gain   lda difficulty_health,y
        sta health,x
        lda difficulty_gain,y
        sta gain_tab,x
        lda difficulty_cost_pwr,y
        sta cost_pwr,x
        lda difficulty_cost_lif,y
        sta cost_lif,x
        lda difficulty_cost_prc,y
        sta cost_prc,x
        iny
        inx
        cpx #7
        bne ?gain
        lda #1
        sta old_fire
        rts
?preset_offset dta 0
.endp

; Direct action keys: P/L/O/E/G/I/S. Modification keys: A/U/D.
; Values are Atari OS CH scan codes (unshifted letters).
.proc read_keyboard
        jsr read_event_keyboard
        bcs ?done
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
        cmp #$0D                ; I - Engines (N is reserved for rejecting offers)
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
        cmp #$21                ; Space closes the modification window
        beq ?cancel
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
        lda story_type
        cmp #8
        bne ?input
        lda relax_release        ; do not instantly close if fire triggered the popup
        bne ?input
        lda STRIG0
        beq ?done
        lda #1
        sta relax_release
?input
        lda STRIG0
        beq ?close
        lda CH
        cmp #$FF
        beq ?done
        and #$3F
        cmp #$21                ; Space
        beq ?close
        cmp #$1C                ; Escape
        beq ?close
        cmp #$0C                ; Return
        bne ?done
?close  lda #$FF
        sta CH
        lda STRIG0
        sta old_fire            ; consume FIRE so it cannot activate the game below
        lda #0
        sta story_type
        jmp draw_screen
?done   rts
.endp

amount_upgraded dta 5,3,7, 6,4,8, 7,5,9
amount_power_prc_cost dta 2,1,0
amount_processing_pwr_cost dta 2,1,1
.proc select_modification      ; X=resource system 0..2
        stx ?system
        lda bit_tab,x
        sta ?bit
        lda modal_type
        cmp #1
        bne ?auto
        lda amount_mask
        and ?bit
        beq ?amount_available
        jmp ?done
?amount_available
        lda amount_mask
        ora ?bit
        sta amount_mask
        lda difficulty
        asl
        clc
        adc difficulty
        clc
        adc ?system
        tax
        lda amount_upgraded,x
        ldx ?system
        sta gain_tab,x
        cpx #0
        bne ?processing_cost
        ldx difficulty
        lda amount_power_prc_cost,x
        sta cost_prc
?processing_cost
        ldx ?system
        cpx #2
        bne ?close
        ldx difficulty
        lda amount_processing_pwr_cost,x
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
        jsr tick_event_result
        jsr draw_progress
        inc frame50
        lda frame50
        cmp #50
        bcc ?r
        lda #0
        sta frame50
        jsr tick_relaxation
        lda story_type
        bne ?r
        jsr tick_events
        lda game_mode
        bne ?r
        dec load_sec
?load   lda load_sec
        ; draw_progress already updates the narrow load strips every frame.
        ; Repainting every complete row once per second made the live columns
        ; visibly flash even though no row content had changed.
        bne ?r
        lda load_interval
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

.proc tick_relaxation
        lda relax_done
        bne ?done
        lda story_type           ; narrative screens pause the one-time timer
        bne ?done
        dec relax_sec
        bne ?done
        lda #1
        sta relax_done
        lda #0
        sta relax_release
        lda #$FF
        sta CH
        lda #8
        sta story_type
        jsr draw_relax_modal
?done   rts
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
        lda radioactive
        cmp #10
        bcc ?systems
        lda #2
        sta game_mode
        lda #7
        sta failure_system
        jsr draw_end
        rts
?systems
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
.proc detect_vbxe               ; C=1 if an FX core answers at either address
        lda VBXE_VCTL
        cmp #$10
        beq ?d6
        lda $D740
        cmp #$10
        beq ?d7
        clc
        rts
?d6     lda #$D6
        bne ?found
?d7     lda #$D7
?found  jsr relocate_vbxe_registers
        sec
        rts
.endp

; Rewrite the high byte of all absolute VBXE register operands. The relocation
; list contains addresses of operand high bytes (instruction label + 2).
.proc relocate_vbxe_registers
        sta ?page+1
        lda #<vbxe_relocations
        sta srcp
        lda #>vbxe_relocations
        sta srcp+1
        ldy #0
?next   lda (srcp),y
        sta dstp
        iny
        lda (srcp),y
        sta dstp+1
        iny
?page   lda #$D6
        ldx #0
        sta (dstp,x)
        cpy #vbxe_relocations_end-vbxe_relocations
        bne ?next
        rts
.endp

vbxe_relocations
        dta a(main.vbreg_main_memac+2),a(main.vbreg_main_vctl+2)
        dta a(setup_xdl.vbreg_setup_xdl_bank+2)
        dta a(enable_display.vbreg_enable_vctl+2),a(enable_display.vbreg_enable_xdl0+2)
        dta a(enable_display.vbreg_enable_xdl1+2),a(enable_display.vbreg_enable_xdl2+2)
        dta a(load_pal.vbreg_palette_psel+2),a(load_pal.vbreg_palette_csel+2)
        dta a(load_pal.vbreg_palette_cr+2),a(load_pal.vbreg_palette_cg+2)
        dta a(load_pal.vbreg_palette_cb+2)
        dta a(font_expand.vbreg_font_bank_on+2),a(font_expand.vbreg_font_bank_off+2)
        dta a(icons_expand.vbreg_icons_bank_on+2),a(icons_expand.vbreg_icons_bank_off+2)
        dta a(blit_init.vbreg_blit_addr0+2),a(blit_init.vbreg_blit_addr1+2)
        dta a(blit_init.vbreg_blit_addr2+2),a(wait_blit.vbreg_wait_blitter+2)
        dta a(do_blit.vbreg_do_blit_bank+2),a(do_blit.vbreg_do_blit_start+2)
        dta a(title_put_pixel.vbreg_title_pixel_bank+2)
        dta a(advance_failure_row.vbreg_failure_row_bank+2)
        dta a(draw_failure_bitmap.vbreg_failure_bank_on+2)
        dta a(draw_failure_bitmap.vbreg_failure_bank_off+2)
        dta a(draw_success_bitmap.vbreg_success_bank_on+2)
        dta a(draw_success_bitmap.vbreg_success_bank_off+2)
        dta a(draw_title_screen.vbreg_title_bank_on+2)
        dta a(draw_title_screen.vbreg_title_bank_off+2)
        dta a(draw_briefing_screen.vbreg_briefing_bank_on+2)
        dta a(draw_briefing_screen.vbreg_briefing_bank_off+2)
        dta a(draw_relax_bitmap.vbreg_relax_bank_on+2)
        dta a(draw_relax_bitmap.vbreg_relax_bank_off+2)
vbxe_relocations_end

; The XDL (VBXE's own display list): 8 overscan lines, then 200 active lines of a
; linear 320-byte-stride overlay reading VRAM $000000 through palette #1.
.proc setup_xdl
        lda #BANK_EN+BANK_XDL
vbreg_setup_xdl_bank
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
vbreg_enable_vctl
        sta VBXE_VCTL
        lda #$00                ; XDL at $07F000
vbreg_enable_xdl0
        sta VBXE_XDL0
        lda #$F0
vbreg_enable_xdl1
        sta VBXE_XDL1
        lda #$07
vbreg_enable_xdl2
        sta VBXE_XDL2
        rts
.endp

; load_pal: (index, r, g, b) quads into VBXE palette #1, terminated by $FF.
;   Writing the blue register auto-advances CSEL, but we set it per colour anyway
;   because the table is sparse.
.proc load_pal
        lda #1
vbreg_palette_psel
        sta VBXE_PSEL
        ldx #0
?l      lda pal_tab,x
        cmp #$FF
        beq ?done
vbreg_palette_csel
        sta VBXE_CSEL
        lda pal_tab+1,x
vbreg_palette_cr
        sta VBXE_CR
        lda pal_tab+2,x
vbreg_palette_cg
        sta VBXE_CG
        lda pal_tab+3,x
vbreg_palette_cb
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
        dta 25,220,224, 62      ; radioactive trefoil
        dta 26, 10, 46, 25      ; low-contrast CRT colour noise
        dta 32,  0,  4,  1      ; title artwork: 16-step green ramp
        dta 33,  1, 12,  2
        dta 34,  2, 22,  4
        dta 35,  3, 34,  6
        dta 36,  5, 48,  8
        dta 37,  7, 64, 11
        dta 38, 10, 82, 14
        dta 39, 14,102, 18
        dta 40, 19,124, 23
        dta 41, 25,148, 29
        dta 42, 33,174, 37
        dta 43, 44,200, 47
        dta 44, 58,222, 58
        dta 45, 78,238, 72
        dta 46,108,250, 88
        dta 47,154,255,112
        dta 48,224,255,232      ; bright briefing body text
        dta 49,246,255,248      ; near-white briefing title/prompt
        dta $FF

;=============================================================================
; font_expand - condensed 5x7 terminal charset -> an 8-bit mask font sheet.
;   ASCII 32..95 maps to glyphs 0..63 by subtracting 32. The narrow source face
;   matches the web UI more closely than the wide Atari OS ROM character set.
;   Each is expanded to 8x8 bytes of 255/0 and padded to a 64-byte cell, so the
;   blitter's source address is base + (gi<<6) with no multiply. 64 cells x 64 B
;   is exactly one 4K bank, which is why the whole sheet fits one window select.
;=============================================================================
rowi    dta 0
dsti    dta 0
bits    dta 0

.proc font_expand
        lda #BANK_EN+FONT_BANK
vbreg_font_bank_on
        sta VBXE_BANK_SEL
        lda #<terminal_font
        sta srcp
        lda #>terminal_font
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
vbreg_font_bank_off
        sta VBXE_BANK_SEL
        rts
?sy     dta 0
.endp

; Five-pixel-wide uppercase terminal face centred in each 8x8 cell. Each glyph
; has a blank baseline row and is stored in ASCII order from space through '_'.
terminal_font
        dta $00,$00,$00,$00,$00,$00,$00,$00 ; 32 space
        dta $10,$10,$10,$10,$10,$00,$10,$00 ; !
        dta $28,$28,$28,$00,$00,$00,$00,$00 ; "
        dta $28,$28,$7C,$28,$7C,$28,$28,$00 ; #
        dta $10,$3C,$50,$38,$14,$78,$10,$00 ; $
        dta $64,$68,$10,$20,$4C,$1C,$00,$00 ; %
        dta $30,$48,$30,$54,$48,$34,$00,$00 ; &
        dta $10,$10,$20,$00,$00,$00,$00,$00 ; '
        dta $08,$10,$20,$20,$20,$10,$08,$00 ; (
        dta $20,$10,$08,$08,$08,$10,$20,$00 ; )
        dta $00,$54,$38,$7C,$38,$54,$00,$00 ; *
        dta $00,$10,$10,$7C,$10,$10,$00,$00 ; +
        dta $00,$00,$00,$00,$00,$10,$10,$20 ; comma
        dta $00,$00,$00,$7C,$00,$00,$00,$00 ; -
        dta $00,$00,$00,$00,$00,$00,$10,$00 ; period
        dta $04,$08,$10,$20,$40,$00,$00,$00 ; /
        dta $38,$44,$4C,$54,$64,$44,$38,$00 ; 0
        dta $10,$30,$10,$10,$10,$10,$38,$00 ; 1
        dta $38,$44,$04,$08,$10,$20,$7C,$00 ; 2
        dta $78,$04,$04,$38,$04,$04,$78,$00 ; 3
        dta $08,$18,$28,$48,$7C,$08,$08,$00 ; 4
        dta $7C,$40,$40,$78,$04,$04,$78,$00 ; 5
        dta $38,$40,$40,$78,$44,$44,$38,$00 ; 6
        dta $7C,$04,$08,$10,$20,$20,$20,$00 ; 7
        dta $38,$44,$44,$38,$44,$44,$38,$00 ; 8
        dta $38,$44,$44,$3C,$04,$04,$38,$00 ; 9
        dta $00,$10,$00,$00,$10,$00,$00,$00 ; :
        dta $00,$10,$00,$00,$10,$10,$20,$00 ; ;
        dta $08,$10,$20,$40,$20,$10,$08,$00 ; <
        dta $00,$00,$7C,$00,$7C,$00,$00,$00 ; =
        dta $20,$10,$08,$04,$08,$10,$20,$00 ; >
        dta $38,$44,$04,$08,$10,$00,$10,$00 ; ?
        dta $38,$44,$5C,$54,$5C,$40,$38,$00 ; @
        dta $38,$44,$44,$7C,$44,$44,$44,$00 ; A
        dta $78,$44,$44,$78,$44,$44,$78,$00 ; B
        dta $38,$44,$40,$40,$40,$44,$38,$00 ; C
        dta $70,$48,$44,$44,$44,$48,$70,$00 ; D
        dta $7C,$40,$40,$78,$40,$40,$7C,$00 ; E
        dta $7C,$40,$40,$78,$40,$40,$40,$00 ; F
        dta $38,$44,$40,$5C,$44,$44,$38,$00 ; G
        dta $44,$44,$44,$7C,$44,$44,$44,$00 ; H
        dta $38,$10,$10,$10,$10,$10,$38,$00 ; I
        dta $1C,$08,$08,$08,$08,$48,$30,$00 ; J
        dta $44,$48,$50,$60,$50,$48,$44,$00 ; K
        dta $40,$40,$40,$40,$40,$40,$7C,$00 ; L
        dta $44,$6C,$54,$54,$44,$44,$44,$00 ; M
        dta $44,$64,$54,$4C,$44,$44,$44,$00 ; N
        dta $38,$44,$44,$44,$44,$44,$38,$00 ; O
        dta $78,$44,$44,$78,$40,$40,$40,$00 ; P
        dta $38,$44,$44,$44,$54,$48,$34,$00 ; Q
        dta $78,$44,$44,$78,$50,$48,$44,$00 ; R
        dta $38,$44,$40,$38,$04,$44,$38,$00 ; S
        dta $7C,$10,$10,$10,$10,$10,$10,$00 ; T
        dta $44,$44,$44,$44,$44,$44,$38,$00 ; U
        dta $44,$44,$44,$44,$44,$28,$10,$00 ; V
        dta $44,$44,$44,$54,$54,$6C,$44,$00 ; W
        dta $44,$44,$28,$10,$28,$44,$44,$00 ; X
        dta $44,$44,$28,$10,$10,$10,$10,$00 ; Y
        dta $7C,$04,$08,$10,$20,$40,$7C,$00 ; Z
        dta $38,$20,$20,$20,$20,$20,$38,$00 ; [
        dta $40,$20,$10,$08,$04,$00,$00,$00 ; backslash
        dta $38,$08,$08,$08,$08,$08,$38,$00 ; ]
        dta $10,$28,$44,$00,$00,$00,$00,$00 ; ^
        dta $00,$00,$00,$00,$00,$00,$7C,$00 ; _

; Eight custom 8x8 icons. The first seven are shared pixel-for-pixel with
; src/game.js; the Atari radioactive icon uses the inverted trefoil only.
; They are expanded once into coloured VBXE sprites; zero remains transparent.
icon_bits
        dta $18,$18,$30,$7C,$18,$30,$20,$00 ; power: bolt
        dta $66,$FF,$FF,$7E,$3C,$18,$00,$00 ; life support: heart
        dta $5A,$5A,$5A,$99,$99,$99,$99,$00 ; processing: Atari Fuji
        dta $C3,$66,$3C,$18,$38,$60,$C0,$00 ; engineering: wrench
        dta $18,$7E,$DB,$FF,$BD,$7E,$42,$00 ; guidance: robot
        dta $18,$3C,$7E,$5A,$5A,$3C,$66,$00 ; engines: rocket
        dta $06,$0C,$58,$30,$30,$7E,$18,$00 ; sensors: dish
        dta $66,$E7,$C3,$00,$18,$00,$3C,$18 ; radioactive: circle-free yellow trefoil
icon_cols dta 18,19,20,21,22,23,24,25
icon_idx  dta 0
icon_rows dta 0
icon_cols_left dta 0

.proc icons_expand
        lda #BANK_EN+ICON_BANK
vbreg_icons_bank_on
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
        cmp #8
        bne ?icon
        lda #0
vbreg_icons_bank_off
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
vbreg_blit_addr0
        sta VBXE_BL_ADR0
        lda #$F1
vbreg_blit_addr1
        sta VBXE_BL_ADR1
        lda #$07
vbreg_blit_addr2
        sta VBXE_BL_ADR2
        rts
.endp

.proc wait_blit
?w
vbreg_wait_blitter
        lda VBXE_BLITTER
        bne ?w
        rts
.endp

.proc do_blit
        jsr wait_blit
        lda #BANK_EN+BANK_XDL
vbreg_do_blit_bank
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
vbreg_do_blit_start
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

; One-pixel corner cut for small parameter points. Unlike fill_round_rect's
; larger radius, a 7x6 cell keeps a five-pixel top/bottom edge and a broad body,
; so it reads as a rounded rectangle instead of a circle.
.proc fill_round_cell
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

        lda rr_x
        clc
        adc #1
        sta calc_x
        lda rr_x+1
        adc #0
        sta calc_x+1
        lda rr_w
        sec
        sbc #2
        sta fr_w
        lda rr_w+1
        sbc #0
        sta fr_w+1
        jsr fill_rect

        lda rr_x
        sta calc_x
        lda rr_x+1
        sta calc_x+1
        lda rr_y
        clc
        adc #1
        sta calc_y
        lda rr_w
        sta fr_w
        lda rr_w+1
        sta fr_w+1
        lda rr_h
        sec
        sbc #2
        sta fr_h
        jsr fill_rect

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
        lda text_x              ; fixed 8px cell advance for the condensed face
        clc
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
; packed artwork
; The title and game-over illustrations use packed 4-bit grayscale. Each source
; pixel expands to a 2x2 VBXE block and indexes the dedicated green ramp 32..47.
;=============================================================================
title_bank     dta 0
title_rows     dta 0
title_cols     dta 0
title_packed   dta 0
title_row_src  dta a(0)
title_next_src dta a(0)

.proc title_put_pixel
        ldy #0
        sta (dstp),y
        inc dstp
        bne ?done
        inc dstp+1
        lda dstp+1
        cmp #$A0
        bne ?done
        lda #$90
        sta dstp+1
        inc title_bank
        lda title_bank
        ora #BANK_EN
vbreg_title_pixel_bank
        sta VBXE_BANK_SEL
?done   rts
.endp

.proc expand_title_row
        lda #80                 ; 160 pixels, two packed per byte
        sta title_cols
?byte  ldy #0
        lda (srcp),y
        sta title_packed
        inc srcp
        bne ?source_ok
        inc srcp+1
?source_ok
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        ora #32
        jsr title_put_pixel
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        ora #32
        jsr title_put_pixel
        lda title_packed
        and #$0F
        ora #32
        jsr title_put_pixel
        lda title_packed
        and #$0F
        ora #32
        jsr title_put_pixel
        dec title_cols
        bne ?byte
        rts
.endp

brief_palette dta 34,39,44,47

.proc expand_briefing_row
        lda #40                 ; 160 two-bit pixels, four packed per byte
        sta title_cols
?byte  ldy #0
        lda (srcp),y
        sta title_packed
        inc srcp
        bne ?source_ok
        inc srcp+1
?source_ok
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel

        lda title_packed
        lsr
        lsr
        lsr
        lsr
        and #3
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel

        lda title_packed
        lsr
        lsr
        and #3
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel

        lda title_packed
        and #3
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel
        dec title_cols
        bne ?byte
        rts
.endp

.proc expand_failure_row
        lda #66                 ; 132 pixels, two packed per byte
        sta title_cols
?byte  ldy #0
        lda (srcp),y
        sta title_packed
        inc srcp
        bne ?source_ok
        inc srcp+1
?source_ok
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        ora #32
        jsr title_put_pixel
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        ora #32
        jsr title_put_pixel
        lda title_packed
        and #$0F
        ora #32
        jsr title_put_pixel
        lda title_packed
        and #$0F
        ora #32
        jsr title_put_pixel
        dec title_cols
        bne ?byte
        rts
.endp

.proc advance_failure_row
        lda dstp
        clc
        adc #56                 ; 320-byte framebuffer row - 264 image pixels
        sta dstp
        bcc ?done
        inc dstp+1
        lda dstp+1
        cmp #$A0
        bne ?done
        lda #$90
        sta dstp+1
        inc title_bank
        lda title_bank
        ora #BANK_EN
vbreg_failure_row_bank
        sta VBXE_BANK_SEL
?done   rts
.endp

.proc draw_failure_bitmap
        jsr wait_blit
        lda #0
        sta title_bank
        lda #BANK_EN
vbreg_failure_bank_on
        sta VBXE_BANK_SEL
        lda #<$915C             ; framebuffer (28, 1)
        sta dstp
        lda #>$915C
        sta dstp+1
        lda #99
        sta title_rows
?row   lda srcp
        sta title_row_src
        lda srcp+1
        sta title_row_src+1
        jsr expand_failure_row
        jsr advance_failure_row
        lda srcp
        sta title_next_src
        lda srcp+1
        sta title_next_src+1
        lda title_row_src
        sta srcp
        lda title_row_src+1
        sta srcp+1
        jsr expand_failure_row
        jsr advance_failure_row
        lda title_next_src
        sta srcp
        lda title_next_src+1
        sta srcp+1
        dec title_rows
        bne ?row
        lda #0
vbreg_failure_bank_off
        sta VBXE_BANK_SEL
        rts
.endp

.proc draw_success_bitmap
        jsr wait_blit
        lda #0
        sta title_bank
        lda #BANK_EN
vbreg_success_bank_on
        sta VBXE_BANK_SEL
        lda #<$915C             ; framebuffer (28, 1)
        sta dstp
        lda #>$915C
        sta dstp+1
        lda #99
        sta title_rows
?row   lda srcp
        sta title_row_src
        lda srcp+1
        sta title_row_src+1
        jsr expand_success_row
        jsr advance_failure_row
        lda srcp
        sta title_next_src
        lda srcp+1
        sta title_next_src+1
        lda title_row_src
        sta srcp
        lda title_row_src+1
        sta srcp+1
        jsr expand_success_row
        jsr advance_failure_row
        lda title_next_src
        sta srcp
        lda title_next_src+1
        sta srcp+1
        dec title_rows
        bne ?row
        lda #0
vbreg_success_bank_off
        sta VBXE_BANK_SEL
        rts
.endp

.proc expand_success_row
        lda #33                 ; 132 two-bit pixels, four packed per byte
        sta title_cols
?byte  ldy #0
        lda (srcp),y
        sta title_packed
        inc srcp
        bne ?source_ok
        inc srcp+1
?source_ok
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel
        lda title_packed
        lsr
        lsr
        lsr
        lsr
        and #3
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel
        lda title_packed
        lsr
        lsr
        and #3
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel
        lda title_packed
        and #3
        tax
        lda brief_palette,x
        jsr title_put_pixel
        lda brief_palette,x
        jsr title_put_pixel
        dec title_cols
        bne ?byte
        rts
.endp

.proc draw_title_screen
        lda #0
        sta title_bank
        lda #BANK_EN
vbreg_title_bank_on
        sta VBXE_BANK_SEL
        lda #<title_bitmap
        sta srcp
        lda #>title_bitmap
        sta srcp+1
        lda #<MEMW
        sta dstp
        lda #>MEMW
        sta dstp+1
        lda #100
        sta title_rows
?row   lda srcp
        sta title_row_src
        lda srcp+1
        sta title_row_src+1
        jsr expand_briefing_row
        lda srcp
        sta title_next_src
        lda srcp+1
        sta title_next_src+1
        lda title_row_src
        sta srcp
        lda title_row_src+1
        sta srcp+1
        jsr expand_briefing_row
        lda title_next_src
        sta srcp
        lda title_next_src+1
        sta srcp+1
        dec title_rows
        bne ?row
        lda #0
vbreg_title_bank_off
        sta VBXE_BANK_SEL

        lda #68
        sta calc_x
        lda #0
        sta calc_x+1
        lda #164
        sta calc_y
        lda #184
        sta fr_w
        lda #0
        sta fr_w+1
        lda #31
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect
        jsr draw_title_difficulty
        lda #80
        sta text_x
        lda #0
        sta text_x+1
        lda #183
        sta text_y
        lda #<s_title_start
        ldx #>s_title_start
        ldy #C_VALUE
        jmp text_at
.endp

difficulty_name_lo dta <s_difficulty_normal,<s_difficulty_easy,<s_difficulty_very_easy
difficulty_name_hi dta >s_difficulty_normal,>s_difficulty_easy,>s_difficulty_very_easy
.proc draw_title_difficulty
        lda #70
        sta calc_x
        lda #0
        sta calc_x+1
        lda #166
        sta calc_y
        lda #180
        sta fr_w
        lda #0
        sta fr_w+1
        lda #10
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
        lda #72
        sta text_x
        lda #0
        sta text_x+1
        lda #169
        sta text_y
        ldx difficulty
        lda difficulty_name_lo,x
        sta txt_ptr
        lda difficulty_name_hi,x
        sta txt_ptr+1
        lda txt_ptr
        ldx txt_ptr+1
        ldy #C_VALUE
        jmp text_at
.endp

brief_ptr dta a(0)
brief_glyph dta 0
brief_x dta a(0)
brief_y dta 0
brief_text_col dta 48
brief_skipped dta 0

.proc draw_brief_glyph
        sta brief_glyph
        lda text_x
        sta brief_x
        lda text_x+1
        sta brief_x+1
        lda text_y
        sta brief_y

        lda #32                 ; near-black artwork colour used as an outline
        sta text_col
        lda brief_x
        sec
        sbc #1
        sta text_x
        lda brief_x+1
        sbc #0
        sta text_x+1
        lda brief_y
        sta text_y
        lda brief_glyph
        jsr draw_char

        lda brief_x
        clc
        adc #1
        sta text_x
        lda brief_x+1
        adc #0
        sta text_x+1
        lda brief_y
        sta text_y
        lda brief_glyph
        jsr draw_char

        lda brief_x
        sta text_x
        lda brief_x+1
        sta text_x+1
        lda brief_y
        sec
        sbc #1
        sta text_y
        lda brief_glyph
        jsr draw_char

        lda brief_x
        sta text_x
        lda brief_x+1
        sta text_x+1
        lda brief_y
        clc
        adc #1
        sta text_y
        lda brief_glyph
        jsr draw_char

        lda brief_x
        sta text_x
        lda brief_x+1
        sta text_x+1
        lda brief_y
        sta text_y
        lda brief_text_col
        sta text_col
        lda brief_glyph
        jmp draw_char
.endp

.proc draw_brief_text
        lda txt_ptr
        sta brief_ptr
        lda txt_ptr+1
        sta brief_ptr+1
?char  lda brief_ptr
        sta txt_ptr
        lda brief_ptr+1
        sta txt_ptr+1
        ldy #0
        lda (txt_ptr),y
        beq ?done
        sec
        sbc #32
        jsr draw_brief_glyph
        inc brief_ptr
        bne ?char
        inc brief_ptr+1
        jmp ?char
?done  rts
.endp

.proc type_brief_line
        lda txt_ptr
        sta brief_ptr
        lda txt_ptr+1
        sta brief_ptr+1
?char  lda brief_ptr
        sta txt_ptr
        lda brief_ptr+1
        sta txt_ptr+1
        ldy #0
        lda (txt_ptr),y
        beq ?done
        sec
        sbc #32
        jsr draw_brief_glyph
        inc brief_ptr
        bne ?wait
        inc brief_ptr+1
?wait
        jsr wait_frame
        jsr wait_frame
        jsr wait_frame
        lda CH
        and #$3F
        cmp #$21                ; Space skips the briefing immediately
        bne ?continue
        lda #$FF
        sta CH
        lda #1
        sta brief_skipped
        rts
?continue
        jmp ?char
?done  rts
.endp

.proc draw_briefing_screen
        lda #0
        sta brief_skipped
        jsr wait_blit
        lda #0
        sta title_bank
        lda #BANK_EN
vbreg_briefing_bank_on
        sta VBXE_BANK_SEL
        lda #<briefing_bitmap
        sta srcp
        lda #>briefing_bitmap
        sta srcp+1
        lda #<MEMW
        sta dstp
        lda #>MEMW
        sta dstp+1
        lda #100
        sta title_rows
?row   lda srcp
        sta title_row_src
        lda srcp+1
        sta title_row_src+1
        jsr expand_briefing_row
        lda srcp
        sta title_next_src
        lda srcp+1
        sta title_next_src+1
        lda title_row_src
        sta srcp
        lda title_row_src+1
        sta srcp+1
        jsr expand_briefing_row
        lda title_next_src
        sta srcp
        lda title_next_src+1
        sta srcp+1
        dec title_rows
        lda title_rows
        cmp #25                 ; final 25 source rows live above BASIC, away
        bne ?more               ; from the $9000-$9FFF VBXE CPU window
        lda #<briefing_bitmap_tail
        sta srcp
        lda #>briefing_bitmap_tail
        sta srcp+1
?more   lda title_rows
        bne ?row
        lda #0
vbreg_briefing_bank_off
        sta VBXE_BANK_SEL

        lda #88
        sta text_x
        lda #0
        sta text_x+1
        lda #12
        sta text_y
        lda #<s_brief_title
        sta txt_ptr
        lda #>s_brief_title
        sta txt_ptr+1
        lda #49
        sta brief_text_col
        jsr draw_brief_text

        lda #48
        sta brief_text_col
        lda #52
        sta text_x
        lda #0
        sta text_x+1
        lda #48
        sta text_y
        lda #<s_brief_line1
        sta txt_ptr
        lda #>s_brief_line1
        sta txt_ptr+1
        jsr type_brief_line
        lda brief_skipped
        beq ?line2
        jmp ?skipped
?line2
        lda #36
        sta text_x
        lda #0
        sta text_x+1
        lda #72
        sta text_y
        lda #<s_brief_line2
        sta txt_ptr
        lda #>s_brief_line2
        sta txt_ptr+1
        jsr type_brief_line
        lda brief_skipped
        beq ?line3
        jmp ?skipped
?line3
        lda #36
        sta text_x
        lda #0
        sta text_x+1
        lda #96
        sta text_y
        lda #<s_brief_line3
        sta txt_ptr
        lda #>s_brief_line3
        sta txt_ptr+1
        jsr type_brief_line
        lda brief_skipped
        beq ?line4
        jmp ?skipped
?line4
        lda #32
        sta text_x
        lda #0
        sta text_x+1
        lda #120
        sta text_y
        lda #<s_brief_line4
        sta txt_ptr
        lda #>s_brief_line4
        sta txt_ptr+1
        jsr type_brief_line
        lda brief_skipped
        beq ?line5
        jmp ?skipped
?line5
        lda #32
        sta text_x
        lda #0
        sta text_x+1
        lda #144
        sta text_y
        lda #<s_brief_line5
        sta txt_ptr
        lda #>s_brief_line5
        sta txt_ptr+1
        jsr type_brief_line
        lda brief_skipped
        bne ?skipped

        lda #80
        sta text_x
        lda #0
        sta text_x+1
        lda #176
        sta text_y
        lda #<s_brief_start
        sta txt_ptr
        lda #>s_brief_start
        sta txt_ptr+1
        lda #49
        sta brief_text_col
        jmp draw_brief_text
?skipped
        rts
.endp

.proc wait_title_input
        lda #$FF
        sta CH
?release
        jsr wait_frame
        lda STRIG0
        beq ?release
?wait   jsr wait_frame
        lda STRIG0
        beq ?start
        lda CH
        and #$3F
        cmp #$21                ; Space
        beq ?start
        cmp #$3A                ; D cycles Normal/Easy/Very Easy
        bne ?wait
        lda #$FF
        sta CH
        inc difficulty
        lda difficulty
        cmp #3
        bcc ?redraw
        lda #0
        sta difficulty
?redraw jsr draw_title_difficulty
        jmp ?wait
?start  lda #$FF
        sta CH
        rts
.endp

.proc wait_continue_input
        lda #$FF
        sta CH
?release
        jsr wait_frame
        lda STRIG0
        beq ?release
?wait   jsr wait_frame
        lda STRIG0
        beq ?start
        lda CH
        and #$3F
        cmp #$21                ; Space
        bne ?wait
?start  lda #$FF
        sta CH
        rts
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

; Resource rows stay compact. Leave a clear separator after the standalone
; Radioactive row, then shift all four main-system rows down together.
row_y_tab dta 18,32,46,80,94,108,122

; Fractional width tables avoid division in the frame loop. A normal cooldown
; advances through eight pixels per second; the speed upgrade uses sixteen.
frac5 dta 0,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,5
frac3 dta 0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
frac10 dta 0,1,1,1,1,1,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,5,5,6,6,7,7,7,7,7,8,8,8,8,8,9,9,9,9,9,10,10,10,10,10,10,10,10
frac20 dta 0,1,1,2,2,2,3,3,4,4,4,5,5,6,6,6,7,7,8,8,8,9,9,10,10,10,11,11,12,12,12,13,13,14,14,14,15,15,16,16,16,17,17,18,18,18,19,19,20,20,20
load_width_easy
        dta 0,3,5,8,10,13,15,18,20,23,25,28,30,33,35,38,40,43,45,48,50,53,55,58,60,60,60,60,60,60,60
load_width_very_easy
        dta 0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58,60

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
        ldx difficulty
        bne ?difficulty_load_width
        sec
        sbc #1
        sta ?seconds
        asl
        clc
        adc ?seconds            ; Normal: (seconds-1) * 3 plus frame fraction
        sta ?loadw
        lda #50
        sec
        sbc frame50
        tay
        lda frac3,y
        clc
        adc ?loadw
        jmp ?load_width_ready
?difficulty_load_width
        lda load_sec
        tay
        ldx difficulty
        dex
        beq ?easy_load_width
        lda load_width_very_easy,y
        bne ?load_width_ready
?easy_load_width
        lda load_width_easy,y
?load_width_ready
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
        jsr fill_round_cell
        jmp ?next
?empty  lda #C_TEXT
        sta fr_col
        jsr fill_round_cell
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

.proc draw_radioactive_row
        lda #20
        sta icon_draw_x
        lda #0
        sta icon_draw_x+1
        lda #63
        sta icon_draw_y
        ldx #7
        jsr draw_icon
        lda #0
        sta status_cell
        lda #BAR_X
        sta status_x
?cell  lda status_x
        sta calc_x
        lda #0
        sta calc_x+1
        lda #64
        sta calc_y
        lda #7
        sta fr_w
        lda #0
        sta fr_w+1
        lda #6
        sta fr_h
        lda status_cell
        cmp radioactive
        bcs ?empty
        lda #C_OFFLINE
        sta fr_col
        jsr fill_round_cell
        jmp ?next
?empty lda #C_TEXT
        sta fr_col
        jsr fill_round_cell
        inc calc_x
        inc calc_y
        lda #5
        sta fr_w
        lda #4
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
?next  inc status_cell
        lda status_x
        clc
        adc #8
        sta status_x
        lda status_cell
        cmp #10
        bne ?cell
        rts
.endp

price_x dta a(0)
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
        lda price_x+1
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
        lda price_x+1
        adc #0
        sta icon_draw_x+1
        lda price_y
        sta icon_draw_y
        ldx term_icon
        jsr draw_icon
        lda price_x
        clc
        adc #24
        sta price_x
        bcc ?advanced
        inc price_x+1
?advanced
        rts
.endp

.proc draw_action_price        ; X=action/system index
        stx price_idx
        lda #140
        sta price_x
        lda #0
        sta price_x+1
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
        lda #0
        sta price_x+1
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

action_key_glyph dta 48,44,47,37,39,41,51 ; P,L,O,E,G,I,S (ASCII-32)
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
        lda #120               ; include the lowered Sensors row and progress bar
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
        lda #0
        sta icon_draw_x+1
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
        jmp draw_radioactive_row
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
        lda #0
        sta icon_draw_x+1
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
        dta 6,15,9,6             ; radioactive
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
        lda #170               ; event panel owns 145..168; clear only legends
        sta calc_y
        lda #296&255
        sta fr_w
        lda #296/256
        sta fr_w+1
        lda #25                ; legend area through scanline 194
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect
        lda #12
        sta tiny_x
        lda #0
        sta tiny_x+1
        lda #175               ; compact two-line footer legend
        sta tiny_y
        lda #<s_power
        ldx #>s_power
        ldy #0
        jsr draw_tiny_legend_item
        lda #84
        sta tiny_x
        lda #<s_life
        ldx #>s_life
        ldy #1
        jsr draw_tiny_legend_item
        lda #164
        sta tiny_x
        lda #<s_process
        ldx #>s_process
        ldy #2
        jsr draw_tiny_legend_item
        lda #244
        sta tiny_x
        lda #<s_radioactive
        ldx #>s_radioactive
        ldy #7
        jsr draw_tiny_legend_item
        lda #12
        sta tiny_x
        lda #0
        sta tiny_x+1             ; clear carry from the long RADIOACTIVE label
        lda #189               ; separated from resources and above the bottom frame
        sta tiny_y
        lda #<s_engineer
        ldx #>s_engineer
        ldy #3
        jsr draw_tiny_legend_item
        lda #84
        sta tiny_x
        lda #<s_guidance
        ldx #>s_guidance
        ldy #4
        jsr draw_tiny_legend_item
        lda #164
        sta tiny_x
        lda #<s_engines
        ldx #>s_engines
        ldy #5
        jsr draw_tiny_legend_item
        lda #244
        sta tiny_x
        lda #0
        sta tiny_x+1
        lda #<s_sensors
        ldx #>s_sensors
        ldy #6
        jsr draw_tiny_legend_item
        jmp draw_event_panel
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
        lda #151
        sta text_y
        lda #<s_denied
        ldx #>s_denied
        ldy #C_OFFLINE
        jmp text_at
.endp

.proc draw_end
        lda game_mode
        cmp #2
        bne ?check_success
        jmp ?lost_image
?check_success
        cmp #1
        beq ?success_image
        jmp ?text_box
?success_image
        lda #24
        sta calc_x
        lda #0
        sta calc_x+1
        sta calc_y
        lda #272&255
        sta fr_w
        lda #272/256
        sta fr_w+1
        lda #200
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect

        lda #<success_bitmap
        sta srcp
        lda #>success_bitmap
        sta srcp+1
        jsr draw_success_bitmap

        lda #32
        sta calc_x
        lda #0
        sta calc_x+1
        lda #145
        sta calc_y
        lda #256&255
        sta fr_w
        lda #256/256
        sta fr_w+1
        lda #48
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect

        lda #40
        sta text_x
        lda #0
        sta text_x+1
        lda #151
        sta text_y
        lda #<s_win_title
        ldx #>s_win_title
        ldy #49
        jsr text_at
        lda #40
        sta text_x
        lda #165
        sta text_y
        lda #<s_success_line1
        ldx #>s_success_line1
        ldy #48
        jsr text_at
        lda #40
        sta text_x
        lda #177
        sta text_y
        lda #<s_success_line2
        ldx #>s_success_line2
        ldy #48
        jmp text_at
?lost_image
        lda failure_system
        cmp #3
        bcc ?valid_image
        jmp ?text_box
?valid_image

        lda #24
        sta calc_x
        lda #0
        sta calc_x+1
        lda #0
        sta calc_y
        lda #272&255
        sta fr_w
        lda #272/256
        sta fr_w+1
        lda #200
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect

        ldx failure_system
        lda failure_image_lo,x
        sta srcp
        lda failure_image_hi,x
        sta srcp+1
        jsr draw_failure_bitmap

        lda #32
        sta calc_x
        lda #0
        sta calc_x+1
        lda #145
        sta calc_y
        lda #256&255
        sta fr_w
        lda #256/256
        sta fr_w+1
        lda #48
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect

        lda #40
        sta text_x
        lda #0
        sta text_x+1
        lda #151
        sta text_y
        ldx failure_system
        cpx #0
        bne ?image_life
        lda #<s_power_fail
        ldx #>s_power_fail
        bne ?image_title
?image_life
        cpx #1
        bne ?image_processing
        lda #<s_life_fail
        ldx #>s_life_fail
        bne ?image_title
?image_processing
        lda #<s_processing_fail
        ldx #>s_processing_fail
?image_title
        ldy #C_OFFLINE
        jsr text_at
        lda #40
        sta text_x
        lda #165
        sta text_y
        lda failure_system
        cmp #0
        bne ?image_life_lines
        lda #<s_power_line1
        ldx #>s_power_line1
        jsr ?image_line1
        lda #<s_power_line2
        ldx #>s_power_line2
        bne ?image_line2
?image_life_lines
        cmp #1
        bne ?image_process_lines
        lda #<s_life_line1
        ldx #>s_life_line1
        jsr ?image_line1
        lda #<s_life_line2
        ldx #>s_life_line2
        bne ?image_line2
?image_process_lines
        lda #<s_process_line1
        ldx #>s_process_line1
        jsr ?image_line1
        lda #<s_process_line2
        ldx #>s_process_line2
?image_line2
        ldy #C_TEXT
        jmp text_at
?image_line1
        ldy #C_TEXT
        jsr text_at
        lda #40
        sta text_x
        lda #177
        sta text_y
        rts

?text_box
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
        jmp text_at
?lost   ldx failure_system
        cpx #7
        bne ?standard_failure
        lda #<s_radioactive_fail
        ldx #>s_radioactive_fail
        jmp ?fail_title
?standard_failure
        cpx #0
        bne ?life
        lda #<s_power_fail
        ldx #>s_power_fail
        jmp ?fail_title
?life   cpx #1
        bne ?processing
        lda #<s_life_fail
        ldx #>s_life_fail
        jmp ?fail_title
?processing
        cpx #2
        bne ?engineering
        lda #<s_processing_fail
        ldx #>s_processing_fail
        jmp ?fail_title
?engineering
        cpx #3
        bne ?guidance
        lda #<s_engineering_fail
        ldx #>s_engineering_fail
        jmp ?fail_title
?guidance
        cpx #4
        bne ?engines
        lda #<s_guidance_fail
        ldx #>s_guidance_fail
        jmp ?fail_title
?engines
        cpx #5
        bne ?sensors
        lda #<s_engine_fail
        ldx #>s_engine_fail
        jmp ?fail_title
?sensors
        lda #<s_sensor_fail
        ldx #>s_sensor_fail
?fail_title ldy #C_OFFLINE
        jsr text_at
        lda #48
        sta text_x
        lda #84
        sta text_y
        lda failure_system
        cmp #7
        bne ?standard_failure_lines
        lda #<s_radioactive_line1
        ldx #>s_radioactive_line1
        jsr ?line1
        lda #<s_radioactive_line2
        ldx #>s_radioactive_line2
        jmp ?line2
?standard_failure_lines
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
        jmp ?line2
?process_lines
        cmp #2
        bne ?engineering_lines
        lda #<s_process_line1
        ldx #>s_process_line1
        jsr ?line1
        lda #<s_process_line2
        ldx #>s_process_line2
        jmp ?line2
?engineering_lines
        cmp #3
        bne ?guidance_lines
        lda #<s_engineering_line1
        ldx #>s_engineering_line1
        jsr ?line1
        lda #<s_engineering_line2
        ldx #>s_engineering_line2
        jmp ?line2
?guidance_lines
        cmp #4
        bne ?engine_lines
        lda #<s_guidance_line1
        ldx #>s_guidance_line1
        jsr ?line1
        lda #<s_guidance_line2
        ldx #>s_guidance_line2
        jmp ?line2
?engine_lines
        cmp #5
        bne ?sensor_lines
        lda #<s_engine_line1
        ldx #>s_engine_line1
        jsr ?line1
        lda #<s_engine_line2
        ldx #>s_engine_line2
        jmp ?line2
?sensor_lines
        lda #<s_sensor_line1
        ldx #>s_sensor_line1
        jsr ?line1
        lda #<s_sensor_line2
        ldx #>s_sensor_line2
?line2  ldy #C_TEXT
        jmp text_at
?line1  ldy #C_TEXT
        jsr text_at
        lda #48
        sta text_x
        lda #96
        sta text_y
        rts
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
        lda #68
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
        lda #0
        sta icon_draw_x+1
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

amount_old_gain dta 2,1,3, 3,2,4, 4,3,5
amount_cost_icon dta 2,0,0
amount_old_cost dta 1,1,1, 1,1,1, 0,0,1
amount_new_gain dta 5,3,7, 6,4,8, 7,5,9
amount_new_cost dta 2,1,2, 1,1,1, 0,0,1
.proc draw_amount_modification_detail
        lda #70
        sta price_x
        lda #0
        sta price_x+1
        lda modal_y
        clc
        adc #10
        sta price_y

        lda difficulty
        asl
        clc
        adc difficulty
        clc
        adc modal_idx
        sta ?detail_idx
        tax
        lda amount_old_gain,x
        ldy #11                 ; '+'
        jsr draw_price_term
        ldx ?detail_idx
        lda amount_old_cost,x
        pha
        ldx modal_idx
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
        lda #0
        sta price_x+1
        ldx ?detail_idx
        lda amount_new_gain,x
        ldy #11
        jsr draw_price_term
        ldx ?detail_idx
        lda amount_new_cost,x
        pha
        ldx modal_idx
        lda amount_cost_icon,x
        tax
        pla
        ldy #13
        jmp draw_price_term
?detail_idx dta 0
.endp

s_power    dta c'POWER',0
s_life     dta c'LIFE SUPPORT',0
s_process  dta c'PROCESSING',0
s_radioactive dta c'RADIOACTIVE',0
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
s_cancel   dta c'SPACE CLOSE',0
s_scan_title dta c'SECTOR SCAN COMPLETE',0
s_plot_title dta c'COURSE PLOTTED',0
s_jump_title dta c'JUMPDRIVE ACTIVATED',0
s_source_title dta c'SOURCE INSTALLED',0
s_story_line1 dta c'OPERATION COMPLETED SUCCESSFULLY.',0
s_story_line2 dta c'THE NEXT SHIP ACTION IS READY.',0
s_relax_line1 dta c'THE SITUATION IS DIFFICULT,',0
s_relax_line2 dta c'BUT LETS HAVE A MOMENT FOR',0
s_relax_line3 dta c'LITTLE RELAX NOW.',0
s_continue dta c'PRESS SPACE TO CONTINUE',0
s_win_title dta c'ALL MAIN SYSTEMS ONLINE',0
s_win_line1 dta c'JUMP COURSE TO THE NEAREST',0
s_win_line2 dta c'SPACEPORT IS READY. YOU WIN!',0
s_success_line1 dta c'JUMP COURSE LOCKED.',0
s_success_line2 dta c'THE CREW ESCAPES THE ABYSS.',0
s_power_fail dta c'POWER SYSTEM FAILURE',0
s_power_line1 dta c'THE REACTOR FALLS SILENT.',0
s_power_line2 dta c'THE LAST LIGHT FADES OUT.',0
s_life_fail dta c'LIFE SUPPORT FAILURE',0
s_life_line1 dta c'OXYGEN FALLS BELOW SURVIVAL.',0
s_life_line2 dta c'NO HEARTBEATS REMAIN.',0
s_processing_fail dta c'PROCESSING CORE FAILURE',0
s_process_line1 dta c'SHIP CONTROL LOOPS COLLAPSE.',0
s_process_line2 dta c'THE CORE BURNS IN SILENCE.',0
s_engineering_fail dta c'ENGINEERING SYSTEM FAILURE',0
s_engineering_line1 dta c'THE HULL CANNOT BE STABILIZED.',0
s_engineering_line2 dta c'THE SHIP BREAKS APART.',0
s_guidance_fail dta c'GUIDANCE SYSTEM FAILURE',0
s_guidance_line1 dta c'THE ORPHEUS LOSES ITS COURSE.',0
s_guidance_line2 dta c'THE ABYSS HAS NO HORIZON.',0
s_engine_fail dta c'ENGINE SYSTEM FAILURE',0
s_engine_line1 dta c'THE JUMP DRIVE FALLS SILENT.',0
s_engine_line2 dta c'THE SHIP DRIFTS FOREVER.',0
s_sensor_fail dta c'SENSOR SYSTEM FAILURE',0
s_sensor_line1 dta c'THE DARKNESS BECOMES ABSOLUTE.',0
s_sensor_line2 dta c'NOTHING ANSWERS THE VOID.',0
s_radioactive_fail dta c'RADIATION LEVEL CRITICAL',0
s_radioactive_line1 dta c'NO LIFE SIGNS DETECTED.',0
s_radioactive_line2 dta c'THE ORPHEUS DRIFTS ON.',0
s_denied   dta c'ACTION LOCKED, COOLING, OR TOO COSTLY',0
s_won      dta c'ALL MAIN SYSTEMS ONLINE!',0
s_lost     dta c'A SHIP SYSTEM WAS DESTROYED.',0
s_title_start dta c'PRESS SPACE TO START',0
s_difficulty_normal dta c'D DIFFICULTY: NORMAL',0
s_difficulty_easy dta c'D DIFFICULTY: EASY',0
s_difficulty_very_easy dta c'D DIFFICULTY: VERY EASY',0
s_brief_title dta c'SHIP EMERGENCY LOG',0
s_brief_line1 dta c'AN ASTEROID STRIKE HAS LEFT',0
s_brief_line2 dta c'YOUR SHIP DRIFTING IN DARKNESS.',0
s_brief_line3 dta c'KEEP POWER, AIR, AND PROCESSING',0
s_brief_line4 dta c'ALIVE WHILE YOU REPAIR THE SHIP.',0
s_brief_line5 dta c'RESTORE MAIN SYSTEMS AND ESCAPE.',0
s_brief_start dta c'PRESS SPACE TO BEGIN',0

failure_image_lo dta <failure_power_bitmap,<failure_power_bitmap,<failure_power_bitmap
failure_image_hi dta >failure_power_bitmap,>failure_power_bitmap,>failure_power_bitmap

failure_power_bitmap
        ; pic/power.png scaled to 132x99 and packed as 4-bit grayscale.
        ; It expands 2x at runtime to 264x198, nearly filling 320x200.
        ins 'atari/gameover-power.4bpp'

success_bitmap
        ; pic/success.png scaled to 132x99 and packed as four grayscale levels.
        ; It expands 2x at runtime to a 264x198 victory picture.
        ins 'atari/success-screen.2bpp'

title_bitmap
        ; pic/girl1.png scaled into a 160x100 four-level title bitmap.
        ; It expands 2x at runtime, saving 4 KB for the success artwork.
        ins 'atari/title-screen.2bpp'

briefing_bitmap
        ; First 75 rows of the 160x100 repair image. Keeping this block below
        ; $9000 prevents MEMAC-A from hiding it while it is being drawn.
        ins 'atari/repair-screen-top.2bpp'

        org $A000
shower_bitmap
        ; pic/shower.png centre-cropped to 8:5, scaled to 160x100, and packed 2bpp.
        ; It expands 2x to fill the complete 320x200 VBXE framebuffer.
        ins 'atari/shower-screen.2bpp'

        org $B000

;=============================================================================
; Random event strip
;   type 0 = idle, 1 = robot decision, 2 = four-digit challenge
;        3 = success, 4 = rejected, 5 = failed/missed
;   mode 0 = salvage, 1 = hazard, 2 = radioactive leak,
;        3 = clear radioactive leak, 4 = robot trade
;=============================================================================
event_type      dta 0
event_mode      dta 0
event_next_sec  dta 0
event_window    dta 0
event_result_frames dta 0       ; fixed short result flash, independent of seconds
event_source    dta 0
event_dest      dta 0
event_gain      dta 0
event_desc      dta 0
event_trade_desc dta 0
event_radio_offer dta 0         ; +1 Radioactive in exchange for another resource
event_rng       dta 1
event_entered   dta 0
event_code      dta 0,0,0,0
event_draw_idx  dta 0
event_scan      dta 0
event_tries     dta 0
event_window_by_difficulty dta 10,12,15

.proc event_random
        lda event_rng
        lsr
        bcc ?store
        eor #$B8
?store sta event_rng
        rts
.endp

.proc event_random3
        jsr event_random
?mod   cmp #3
        bcc ?done
        sec
        sbc #3
        bcs ?mod
?done  rts
.endp

.proc event_random10
        jsr event_random
?mod   cmp #10
        bcc ?done
        sec
        sbc #10
        bcs ?mod
?done  rts
.endp

.proc schedule_next_event
        jsr event_random
?mod   cmp #5
        bcc ?ready
        sec
        sbc #5
        bcs ?mod
?ready clc
        adc #1                  ; blank pause of 1..5 seconds between events
        ldx difficulty
        beq ?store
        clc
        adc difficulty
        adc difficulty          ; Easy +2 seconds, Very Easy +4 seconds
?store
        sta event_next_sec
        rts
.endp

.proc init_events
        lda RTCLOK+2
        eor RTCLOK+1
        eor VCOUNT
        bne ?seed
        lda #$A7
?seed   sta event_rng
        lda #0
        sta event_type
        sta event_mode
        sta event_window
        sta event_entered
        sta event_result_frames
        jsr schedule_next_event
        rts
.endp

.proc start_random_event
        lda #0
        sta event_radio_offer
        jsr event_random
        and #3
        cmp #3                  ; three out of four events are robot trades
        beq ?code

        ; Some robot offers grant a normal resource while adding one point of
        ; Radioactive as the cost instead of deducting a normal resource.
        jsr event_random
        and #3
        bne ?normal_trade
        lda radioactive
        cmp #10
        bcs ?normal_trade
        lda #1
        sta event_radio_offer
        lda #7
        sta event_source
        jsr event_random3
        sta event_dest
        jmp ?trade_gain

        ; Find a resource with at least two points, so accepting a trade can
        ; never destroy Power, Life Support, or Processing immediately.
?normal_trade
        jsr event_random3
        sta event_source
        lda #3
        sta event_tries
?source
        ldx event_source
        lda health,x
        cmp #2
        bcs ?source_ready
        inc event_source
        lda event_source
        cmp #3
        bcc ?source_next
        lda #0
        sta event_source
?source_next
        dec event_tries
        bne ?source
        jmp ?code               ; no safe trade is possible; use a code event

?source_ready
?dest   jsr event_random3
        cmp event_source
        beq ?dest
        sta event_dest
?trade_gain
        lda difficulty
        clc
        adc #2
        sta event_gain          ; trade one point for two elsewhere
        jsr event_random
        and #3
        sta event_trade_desc
        ldx difficulty
        lda event_window_by_difficulty,x
        sta event_window        ; same ten-second window as code challenges
        lda #4
        sta event_mode
        lda #1
        sta event_type
        jmp draw_event_panel

?code   jsr event_random
        and #3
        cmp #2
        bne ?check_cleanup
        ldx radioactive         ; only offer a leak when all two points fit
        cpx #9
        bcc ?store_mode
        lda #0                  ; otherwise fall back to salvage
        jmp ?store_mode
?check_cleanup
        cmp #3
        bne ?store_mode
        ldx radioactive         ; cleanup always removes exactly two points
        cpx #2
        bcs ?store_mode
        lda #1                  ; otherwise fall back to a hazard
?store_mode
        sta event_mode
        cmp #2
        bcs ?radioactive_target
        jsr event_random3
        sta event_dest
        jsr event_random
        and #1
        clc
        adc #1
        sta event_gain
        lda event_mode
        bne ?hazard_gain
        lda event_gain
        clc
        adc difficulty          ; salvage improves with easier presets
        sta event_gain
        jmp ?description
?hazard_gain
        lda difficulty
        beq ?description        ; Normal hazards retain their random 1..2 loss
        lda #1
        sta event_gain
?description
        jsr event_random
        and #3
        sta event_desc
        jmp ?prepare_code
?radioactive_target
        lda #7
        sta event_dest
        lda event_mode
        cmp #3
        beq ?cleanup_gain
        lda difficulty
        beq ?normal_radioactive_gain
        lda #1                  ; easier leak failures add only one point
        bne ?store_radioactive_gain
?normal_radioactive_gain
        lda #2
        bne ?store_radioactive_gain
?cleanup_gain
        lda difficulty
        clc
        adc #2                  ; cleanup removes 2/3/4 points
?store_radioactive_gain
        sta event_gain
?radioactive_desc
        lda #0
        sta event_desc
?prepare_code
        lda #0
        sta event_entered
        ldx #0
?digit  stx event_draw_idx
        jsr event_random10
        ldx event_draw_idx
        sta event_code,x
        inx
        cpx #4
        bne ?digit
        ldx difficulty
        lda event_window_by_difficulty,x
        sta event_window
        lda #2
        sta event_type
        jmp draw_event_panel
.endp

.proc tick_events
        lda event_type
        beq ?waiting
        cmp #1
        bne ?check_code
        dec event_window
        bne ?trade_running
        lda #4                  ; unanswered trade is rejected
        sta event_type
        lda #20
        sta event_result_frames
        jmp draw_event_panel
?trade_running
        ; The description, category label, and frame are static for the whole
        ; offer. Refreshing the complete panel every second made them flash;
        ; only the countdown strip changes while the offer is active.
        jmp draw_event_progress
?check_code
        cmp #2
        bne ?result
        dec event_window
        bne ?code_running
        jmp event_code_failed
?code_running
        ; Keep the challenge contents stable and update only its countdown.
        jmp draw_event_progress
?result
        rts                     ; frame-based tick_event_result owns result timing
?waiting
        dec event_next_sec
        beq ?start
        rts                     ; the idle panel is already clear
?start
        jmp start_random_event
?done   rts
.endp

digit_scan_codes
        dta $32,$1F,$1E,$1A,$18,$1D,$1B,$33,$35,$30 ; 0..9

.proc scan_event_digit         ; event_scan -> A=digit and C=1, or C=0
        ldx #9
?find  lda digit_scan_codes,x
        cmp event_scan
        beq ?found
        dex
        bpl ?find
        clc
        rts
?found txa
        sec
        rts
.endp

.proc read_event_keyboard      ; C=1 when the event consumed CH
        lda event_type
        cmp #1
        beq ?decision
        cmp #2
        beq ?code
        clc
        rts
?decision
        lda CH
        cmp #$FF
        beq ?unused
        and #$3F
        cmp #$2B                ; Y
        beq ?accept
        cmp #$23                ; N
        beq ?reject
?unused clc
        rts
?accept
        lda #$FF
        sta CH
        jsr accept_robot_event
        sec
        rts
?reject
        lda #$FF
        sta CH
        lda #4
        sta event_type
        lda #20                 ; show result and category together for 0.4 seconds
        sta event_result_frames
        jsr draw_event_panel
        sec
        rts
?code   lda CH
        cmp #$FF
        beq ?unused
        and #$3F
        sta event_scan
        jsr scan_event_digit
        bcc ?unused
        sta event_scan
        lda #$FF
        sta CH
        ldx event_entered
        lda event_code,x
        cmp event_scan
        bne ?wrong
        inc event_entered
        lda event_entered
        cmp #4
        beq ?complete
        jsr draw_event_panel
        sec
        rts
?wrong  jsr draw_event_panel     ; wrong digits are ignored and never displayed
        sec
        rts
?complete
        jsr event_code_success
        sec
        rts
.endp

.proc add_event_resource       ; A=amount, X=Power/Life/Processing
        clc
        adc health,x
        cmp #11
        bcc ?store
        lda #10
?store sta health,x
        rts
.endp

.proc subtract_event_resource  ; A=amount, X=Power/Life/Processing
        sta event_scan
        lda health,x
        sec
        sbc event_scan
        bcs ?store
        lda #0
?store sta health,x
        rts
.endp

.proc redraw_after_event
        jsr check_end
        lda game_mode
        bne ?done
        jsr draw_rows
        jsr draw_footer
?done   rts
.endp

.proc accept_robot_event
        lda event_radio_offer
        beq ?normal_cost
        inc radioactive
        jmp ?reward
?normal_cost
        ldx event_source
        lda #1
        jsr subtract_event_resource
?reward
        ldx event_dest
        lda event_gain
        jsr add_event_resource
        lda #3
        sta event_type
        lda #20
        sta event_result_frames
        jmp redraw_after_event
.endp

.proc event_code_success
        lda #0
        sta event_entered
        lda event_mode
        beq ?salvage
        cmp #3
        bne ?prevented
        lda radioactive
        beq ?prevented
        sec
        sbc event_gain
        bcs ?store_radioactive
        lda #0
?store_radioactive
        sta radioactive
        jmp ?prevented
?salvage
        ldx event_dest
        lda event_gain
        jsr add_event_resource
?prevented
        lda #3
        sta event_type
        lda #20
        sta event_result_frames
        jmp redraw_after_event
.endp

.proc event_code_failed
        lda #0
        sta event_entered
        lda event_mode
        beq ?missed              ; missed salvage has no additional penalty
        cmp #2
        beq ?radioactive_leak
        cmp #3
        beq ?missed              ; failed cleanup leaves radiation unchanged
        ldx event_dest
        lda event_gain
        jsr subtract_event_resource
        jmp ?missed
?radioactive_leak
        lda radioactive
        clc
        adc event_gain
        cmp #11
        bcc ?store_radioactive
        lda #10
?store_radioactive
        sta radioactive
?missed lda #5
        sta event_type
        lda #20
        sta event_result_frames
        jmp redraw_after_event
.endp

; Result text and its OPPORTUNITY/CHALLENGE label must clear on the same frame.
; A frame counter also avoids the old 0..1 second lifetime caused by alignment
; with the once-per-second event tick.
.proc tick_event_result
        lda event_type
        cmp #3
        bcc ?done
        lda event_result_frames
        beq ?clear
        dec event_result_frames
        bne ?done
?clear  lda #0
        sta event_type
        sta event_window
        jsr schedule_next_event
        jmp draw_event_panel
?done   rts
.endp

.proc draw_event_digits        ; four target digits at the current text cursor
        lda #C_VALUE
        sta text_col
        ldx #0
?digit  stx event_draw_idx
        cpx event_entered
        bcc ?hidden
        lda event_code,x
        clc
        adc #16
        bne ?draw
?hidden lda #0                  ; correct leading digits disappear
?draw
        jsr draw_char
        ldx event_draw_idx
        inx
        cpx #4
        bne ?digit
        rts
.endp

event_width_normal_lo dta <0,<27,<55,<82,<110,<138,<165,<193,<220,<248,<276,<276,<276,<276,<276,<276
event_width_normal_hi dta >0,>27,>55,>82,>110,>138,>165,>193,>220,>248,>276,>276,>276,>276,>276,>276
event_width_easy_lo dta <0,<23,<46,<69,<92,<115,<138,<161,<184,<207,<230,<253,<276,<276,<276,<276
event_width_easy_hi dta >0,>23,>46,>69,>92,>115,>138,>161,>184,>207,>230,>253,>276,>276,>276,>276
event_width_very_easy_lo dta <0,<18,<37,<55,<74,<92,<110,<129,<147,<166,<184,<202,<221,<239,<258,<276
event_width_very_easy_hi dta >0,>18,>37,>55,>74,>92,>110,>129,>147,>166,>184,>202,>221,>239,>258,>276

.proc draw_event_progress
        lda #20
        sta calc_x
        lda #0
        sta calc_x+1
        lda #165
        sta calc_y
        lda #<276
        sta fr_w
        lda #>276
        sta fr_w+1
        lda #2
        sta fr_h
        lda #C_SELECT
        sta fr_col
        jsr fill_rect
        ldx event_window
        lda difficulty
        beq ?normal_width
        cmp #1
        beq ?easy_width
        lda event_width_very_easy_lo,x
        sta fr_w
        lda event_width_very_easy_hi,x
        jmp ?width_ready
?easy_width
        lda event_width_easy_lo,x
        sta fr_w
        lda event_width_easy_hi,x
        jmp ?width_ready
?normal_width
        lda event_width_normal_lo,x
        sta fr_w
        lda event_width_normal_hi,x
?width_ready
        sta fr_w+1
        ora fr_w
        beq ?done
        lda #C_COOLDOWN
        sta fr_col
        jsr fill_rect
?done   rts
.endp

.proc draw_event_effect
        lda #240
        sta price_x
        lda #0
        sta price_x+1
        lda #157
        sta price_y
        lda event_mode
        cmp #2
        beq ?radioactive_gain
        cmp #3
        beq ?radioactive_loss
        cmp #1
        beq ?loss
        lda event_gain
        ldx event_dest
        ldy #11                 ; '+' followed by the resource icon
        jmp draw_price_term
?loss   lda event_gain
        ldx event_dest
        ldy #13                 ; '-' followed by the resource icon
        jmp draw_price_term
?radioactive_gain
        lda event_gain
        ldx #7
        ldy #11
        jmp draw_price_term
?radioactive_loss
        lda event_gain
        ldx #7
        ldy #13
        jmp draw_price_term
.endp

salvage_desc_lo dta <s_event_alpha,<s_event_research,<s_event_drone,<s_event_relay
salvage_desc_hi dta >s_event_alpha,>s_event_research,>s_event_drone,>s_event_relay
hazard_desc_lo dta <s_event_leak,<s_event_fire,<s_event_surge,<s_event_core
hazard_desc_hi dta >s_event_leak,>s_event_fire,>s_event_surge,>s_event_core
trade_desc_lo dta <s_trade_opportunity,<s_trade_want,<s_trade_option,<s_trade_offer
trade_desc_hi dta >s_trade_opportunity,>s_trade_want,>s_trade_option,>s_trade_offer

.proc draw_event_panel
        lda #12
        sta calc_x
        lda #0
        sta calc_x+1
        lda #145               ; clear the panel and the small label above it
        sta calc_y
        lda #296&255
        sta fr_w
        lda #296/256
        sta fr_w+1
        lda #24
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_rect

        lda event_type
        bne ?active
        rts
?active
        lda #12
        sta calc_x
        lda #151
        sta calc_y
        lda #296&255
        sta fr_w
        lda #296/256
        sta fr_w+1
        lda #18
        sta fr_h
        lda #C_BORDER
        sta fr_col
        jsr fill_round_rect
        lda #14
        sta calc_x
        lda #153
        sta calc_y
        lda #292&255
        sta fr_w
        lda #292/256
        sta fr_w+1
        lda #14
        sta fr_h
        lda #C_WIN
        sta fr_col
        jsr fill_round_rect

        ; Label the event category above the upper-left edge using the same
        ; compact 3x5 font as the footer legend.
        lda #20
        sta tiny_x
        lda #0
        sta tiny_x+1
        lda #146
        sta tiny_y
        lda event_type
        cmp #1
        beq ?opportunity_label
        cmp #2
        beq ?challenge_label
        lda event_mode           ; completed robot trades remain opportunities
        cmp #4
        beq ?opportunity_label
?challenge_label
        lda #<s_event_challenge
        ldx #>s_event_challenge
        bne ?draw_category
?opportunity_label
        lda #<s_trade_opportunity
        ldx #>s_trade_opportunity
?draw_category
        jsr draw_tiny_text

        lda event_type
        cmp #1
        beq ?decision
        cmp #2
        beq ?code
        jmp ?result

?decision
        lda #20
        sta text_x
        lda #0
        sta text_x+1
        lda #157
        sta text_y
        ldx event_trade_desc
        lda trade_desc_lo,x
        sta txt_ptr
        lda trade_desc_hi,x
        sta txt_ptr+1
        lda txt_ptr
        ldx txt_ptr+1
        ldy #C_TITLE
        jsr text_at
        lda #124
        sta price_x
        lda #0
        sta price_x+1
        lda #157
        sta price_y
        lda #1
        ldx event_source
        ldy #13
        pha
        lda event_radio_offer
        beq ?normal_offer_sign
        ldy #11
?normal_offer_sign
        pla
        jsr draw_price_term
        lda event_gain
        ldx event_dest
        ldy #11
        jsr draw_price_term
        lda #252
        sta text_x
        lda #0
        sta text_x+1
        lda #157
        sta text_y
        lda #<s_event_yes_no
        ldx #>s_event_yes_no
        ldy #C_VALUE
        jsr text_at
        jmp draw_event_progress

?code   lda #20
        sta text_x
        lda #0
        sta text_x+1
        lda #157
        sta text_y
        ldx event_desc
        lda event_mode
        cmp #2
        beq ?radioactive_leak
        cmp #3
        beq ?radioactive_clear
        cmp #1
        beq ?hazard
        lda salvage_desc_lo,x
        sta txt_ptr
        lda salvage_desc_hi,x
        sta txt_ptr+1
        bne ?code_title
?hazard lda hazard_desc_lo,x
        sta txt_ptr
        lda hazard_desc_hi,x
        sta txt_ptr+1
        bne ?code_title
?radioactive_leak
        lda #<s_event_radioactive_leak
        sta txt_ptr
        lda #>s_event_radioactive_leak
        sta txt_ptr+1
        bne ?code_title
?radioactive_clear
        lda #<s_event_radioactive_clear
        sta txt_ptr
        lda #>s_event_radioactive_clear
        sta txt_ptr+1
?code_title
        lda txt_ptr
        ldx txt_ptr+1
        ldy #C_TITLE
        jsr text_at
        lda #200
        sta text_x
        jsr draw_event_digits
        jsr draw_event_effect
        jmp draw_event_progress

?result
        lda #20
        sta text_x
        lda #0
        sta text_x+1
        lda #157
        sta text_y
        lda event_type
        cmp #4
        beq ?rejected
        cmp #5
        beq ?failed
        lda event_mode
        cmp #1
        beq ?prevented
        cmp #2
        beq ?leak_prevented
        cmp #3
        beq ?radioactive_cleared
        cmp #4
        beq ?trade_done
        lda #<s_event_success
        ldx #>s_event_success
        bne ?result_text
?prevented
        lda #<s_event_prevented
        ldx #>s_event_prevented
        bne ?plain_effect
?leak_prevented
        lda #<s_event_leak_prevented
        ldx #>s_event_leak_prevented
        bne ?result_text
?radioactive_cleared
        lda #<s_event_radioactive_cleared
        ldx #>s_event_radioactive_cleared
        bne ?result_text
?trade_done
        lda #<s_event_trade_done
        ldx #>s_event_trade_done
        bne ?result_text
?rejected
        lda #<s_event_rejected
        ldx #>s_event_rejected
        bne ?plain_result
?failed
        lda event_mode
        beq ?salvage_missed
        cmp #2
        beq ?radioactive_increased
        cmp #3
        beq ?cleanup_failed
        lda #<s_event_failed
        ldx #>s_event_failed
        bne ?failed_text
?radioactive_increased
        lda #<s_event_radioactive_increased
        ldx #>s_event_radioactive_increased
        bne ?failed_text
?cleanup_failed
        lda #<s_event_cleanup_failed
        ldx #>s_event_cleanup_failed
        bne ?failed_text
?salvage_missed
        lda #<s_event_missed
        ldx #>s_event_missed
        bne ?plain_effect
?failed_text
        ldy #C_OFFLINE
        jsr text_at
        jmp draw_event_effect
?result_text
        ldy #C_ONLINE
        jsr text_at
        lda event_mode
        cmp #4
        bne ?draw_result_effect
        lda event_radio_offer
        beq ?draw_result_effect
        lda #216
        sta price_x
        lda #0
        sta price_x+1
        lda #157
        sta price_y
        lda #1
        ldx #7
        ldy #11
        jsr draw_price_term
?draw_result_effect
        jmp draw_event_effect
?plain_effect
        ldy #C_TEXT
        jsr text_at
        jmp draw_event_effect
?plain_result
        ldy #C_TEXT
        jmp text_at
.endp

s_trade_opportunity dta c'OPPORTUNITY',0
s_event_challenge  dta c'CHALLENGE',0
s_trade_want      dta c'DO YOU WANT',0
s_trade_option    dta c'HAVE OPTION',0
s_trade_offer     dta c'ROBOT OFFER',0
s_event_yes_no    dta c'Y/N',0
s_event_alpha     dta c'ALPHA MACHINE',0
s_event_research  dta c'HELP RESEARCH',0
s_event_drone     dta c'REPAIR DRONE',0
s_event_relay     dta c'RESTORE RELAY',0
s_event_leak      dta c'COOLANT LEAK',0
s_event_fire      dta c'RESEARCH FIRE',0
s_event_surge     dta c'POWER SURGE',0
s_event_core      dta c'CORE FAILURE',0
s_event_radioactive_leak dta c'RADIOACTIVE LEAK',0
s_event_radioactive_clear dta c'CLEAR RADIOACTIVE LEAK',0
s_event_success   dta c'SALVAGE SECURED',0
s_event_prevented dta c'HAZARD PREVENTED',0
s_event_leak_prevented dta c'LEAK PREVENTED',0
s_event_radioactive_cleared dta c'RADIOACTIVE CLEARED',0
s_event_radioactive_increased dta c'RADIOACTIVE INCREASED',0
s_event_cleanup_failed dta c'CLEANUP FAILED',0
s_event_trade_done dta c'ROBOT TRADE DONE',0
s_event_rejected  dta c'ROBOT OFFER REJECTED',0
s_event_failed    dta c'CODE FAILED',0
s_event_missed    dta c'SALVAGE MISSED',0

.proc draw_relax_bitmap
        jsr wait_blit
        lda #0
        sta title_bank
        lda #BANK_EN
vbreg_relax_bank_on
        sta VBXE_BANK_SEL
        lda #<shower_bitmap
        sta srcp
        lda #>shower_bitmap
        sta srcp+1
        lda #<MEMW
        sta dstp
        lda #>MEMW
        sta dstp+1
        lda #100
        sta title_rows
?row   lda srcp
        sta title_row_src
        lda srcp+1
        sta title_row_src+1
        jsr expand_briefing_row
        lda srcp
        sta title_next_src
        lda srcp+1
        sta title_next_src+1
        lda title_row_src
        sta srcp
        lda title_row_src+1
        sta srcp+1
        jsr expand_briefing_row
        lda title_next_src
        sta srcp
        lda title_next_src+1
        sta srcp+1
        dec title_rows
        bne ?row
        lda #0
vbreg_relax_bank_off
        sta VBXE_BANK_SEL
        rts
.endp

.proc draw_relax_modal
        jsr draw_relax_bitmap
        lda #0
        sta relax_type_skip
        lda #52
        sta text_x
        lda #0
        sta text_x+1
        lda #148
        sta text_y
        lda #<s_relax_line1
        sta txt_ptr
        lda #>s_relax_line1
        sta txt_ptr+1
        lda #49
        sta brief_text_col
        jsr type_relax_line
        lda relax_type_skip
        bne ?skip
        lda #56
        sta text_x
        lda #0
        sta text_x+1
        lda #162
        sta text_y
        lda #<s_relax_line2
        sta txt_ptr
        lda #>s_relax_line2
        sta txt_ptr+1
        lda #48
        sta brief_text_col
        jsr type_relax_line
        lda relax_type_skip
        bne ?skip
        lda #92
        sta text_x
        lda #0
        sta text_x+1
        lda #176
        sta text_y
        lda #<s_relax_line3
        sta txt_ptr
        lda #>s_relax_line3
        sta txt_ptr+1
        jsr type_relax_line
        lda relax_type_skip
        bne ?skip
        lda #68
        sta text_x
        lda #0
        sta text_x+1
        lda #188
        sta text_y
        lda #<s_relax_continue
        sta txt_ptr
        lda #>s_relax_continue
        sta txt_ptr+1
        lda #49
        sta brief_text_col
        jmp draw_brief_text
?skip   lda STRIG0
        sta old_fire            ; consume the FIRE press used to skip typing
        lda #$FF
        sta CH                  ; consume the Space press used to skip typing
        lda #0
        sta story_type
        jmp draw_screen
.endp

; The relaxation popup uses the briefing's outlined glyph renderer, but its
; per-character delay watches both Space and FIRE. A held controller button must
; first be released, preventing the action that opened the screen from
; dismissing it immediately.
relax_type_skip dta 0

.proc relax_char_delay
        ldx #3
?frame jsr wait_frame
        lda CH
        and #$3F
        cmp #$21                ; Space skips typing and closes the popup
        bne ?fire
        lda #$FF
        sta CH
        lda #1
        sta relax_type_skip
        rts
?fire
        lda relax_release
        bne ?armed
        lda STRIG0
        beq ?next
        lda #1
        sta relax_release
        bne ?next
?armed  lda STRIG0
        bne ?next
        lda #1
        sta relax_type_skip
        rts
?next   dex
        bne ?frame
        rts
.endp

.proc type_relax_line
        lda txt_ptr
        sta brief_ptr
        lda txt_ptr+1
        sta brief_ptr+1
?char  lda brief_ptr
        sta txt_ptr
        lda brief_ptr+1
        sta txt_ptr+1
        ldy #0
        lda (txt_ptr),y
        beq ?done
        sec
        sbc #32
        jsr draw_brief_glyph
        inc brief_ptr
        bne ?wait
        inc brief_ptr+1
?wait   jsr relax_char_delay
        lda relax_type_skip
        beq ?char
?done   rts
.endp

s_relax_continue dta c'PRESS SPACE TO CONTINUE',0

        org $BC00
briefing_bitmap_tail
        ; Final 25 repair rows, stored in RAM exposed beneath BASIC ROM.
        ins 'atari/repair-screen-tail.2bpp'

        run main
