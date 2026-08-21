// Converts USB HID keycodes from gpio_usb_keycode_0/1 into Lynx input registers.
// The eight keycode bytes are searched with has_key(). Arrow keys and keypad
// keys drive the Lynx direction bits in lynx_fcb0_joystick. Z/A drive Inside,
// X/B drive Outside, Enter drives Option 1, and Space drives Pause.
// lynx_fcb1_switches keeps both cart inactive bits high and uses bit 0 for Pause.

`timescale 1ns/1ps

module keycode_to_lynx (
    input  logic [31:0] gpio_usb_keycode_0,
    input  logic [31:0] gpio_usb_keycode_1,

    output logic [7:0]  lynx_fcb0_joystick,
    output logic [2:0]  lynx_fcb1_switches
);

    localparam logic [7:0] HID_A        = 8'h04;
    localparam logic [7:0] HID_B        = 8'h05;
    localparam logic [7:0] HID_X        = 8'h1B;
    localparam logic [7:0] HID_Z        = 8'h1D;
    localparam logic [7:0] HID_ENTER    = 8'h28;
    localparam logic [7:0] HID_SPACE    = 8'h2C;

    localparam logic [7:0] HID_RIGHT    = 8'h4F;
    localparam logic [7:0] HID_LEFT     = 8'h50;
    localparam logic [7:0] HID_DOWN     = 8'h51;
    localparam logic [7:0] HID_UP       = 8'h52;

    localparam logic [7:0] HID_KP1      = 8'h59;
    localparam logic [7:0] HID_KP2      = 8'h5A;
    localparam logic [7:0] HID_KP3      = 8'h5B;
    localparam logic [7:0] HID_KP4      = 8'h5C;
    localparam logic [7:0] HID_KP5      = 8'h5D;
    localparam logic [7:0] HID_KP6      = 8'h5E;
    localparam logic [7:0] HID_KP7      = 8'h5F;
    localparam logic [7:0] HID_KP8      = 8'h60;
    localparam logic [7:0] HID_KP9      = 8'h61;

    logic [7:0] kc [0:7];

    always_comb begin
        kc[0] = gpio_usb_keycode_0[7:0];
        kc[1] = gpio_usb_keycode_0[15:8];
        kc[2] = gpio_usb_keycode_0[23:16];
        kc[3] = gpio_usb_keycode_0[31:24];

        kc[4] = gpio_usb_keycode_1[7:0];
        kc[5] = gpio_usb_keycode_1[15:8];
        kc[6] = gpio_usb_keycode_1[23:16];
        kc[7] = gpio_usb_keycode_1[31:24];
    end

    function automatic logic has_key;
        input logic [7:0] code;
        begin
            has_key = 1'b0;

            for (int i = 0; i < 8; i = i + 1) begin
                if (kc[i] == code) begin
                    has_key = 1'b1;
                end
            end
        end
    endfunction

    logic key_1;
    logic key_2;
    logic key_3;
    logic key_4;
    logic key_5;
    logic key_6;
    logic key_7;
    logic key_8;
    logic key_9;

    logic key_up;
    logic key_down;
    logic key_left;
    logic key_right;

    logic key_inside;
    logic key_outside;
    logic key_option1;
    logic key_option2;
    logic key_pause;

    always_comb begin
        key_1 = has_key(HID_KP1);
        key_2 = has_key(HID_KP2);
        key_3 = has_key(HID_KP3);
        key_4 = has_key(HID_KP4);
        key_5 = has_key(HID_KP5);
        key_6 = has_key(HID_KP6);
        key_7 = has_key(HID_KP7);
        key_8 = has_key(HID_KP8);
        key_9 = has_key(HID_KP9);

        key_up    = key_7 | key_8 | key_9 | has_key(HID_UP);
        key_down  = key_1 | key_2 | key_3 | has_key(HID_DOWN);
        key_left  = key_1 | key_4 | key_7 | has_key(HID_LEFT);
        key_right = key_3 | key_6 | key_9 | has_key(HID_RIGHT);

        key_inside  = has_key(HID_Z) | has_key(HID_A);
        key_outside = has_key(HID_X) | has_key(HID_B);
        key_option1 = has_key(HID_ENTER);
        key_option2 = 1'b0;
        key_pause   = has_key(HID_SPACE);

        lynx_fcb0_joystick[7] = key_down;
        lynx_fcb0_joystick[6] = key_up;
        lynx_fcb0_joystick[5] = key_right;
        lynx_fcb0_joystick[4] = key_left;

        lynx_fcb0_joystick[3] = key_option1;
        lynx_fcb0_joystick[2] = key_option2;
        lynx_fcb0_joystick[1] = key_inside;
        lynx_fcb0_joystick[0] = key_outside;

        lynx_fcb1_switches[2] = 1'b1;
        lynx_fcb1_switches[1] = 1'b1;
        lynx_fcb1_switches[0] = key_pause;
    end

endmodule