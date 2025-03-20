#Requires AutoHotkey v2.0
Persistent

class HotCorner {
    ; Core functionality settings
    static triggered := false
    static enabled := true                  ; Script starts enabled
    static cornerSize := 15                 ; Will be recalculated based on screen size
    static mouseHook := 0
    static glowLayers := []                 ; Store glow layer GUIs
    static glowRadius := 50                 ; Will be recalculated based on screen size
    
    ; Performance optimization tracking
    static lastX := -1                      ; Track last mouse position for throttling
    static lastY := -1
    static updateThreshold := 1             ; Minimum pixels moved to trigger update
    static timerActive := false             ; Track if timer is running
    static updateInterval := 16             ; ~60fps refresh rate
    static isVisible := false               ; Track if glow is visible
    static lastTickCount := 0               ; For performance timing
    static minUpdateInterval := 10          ; Minimum ms between updates
    static timerFunc := 0                   ; Store timer function reference
    static lastTriggerTime := 0             ; Prevents double-triggering
    static triggerCooldown := 250           ; Ms between allowed triggers
    static layerPropsCache := []            ; Cache for layer properties
    
    ; Mouse position tracking
    static mouseOutOfRange := true          ; Track when mouse is far from corner
    static farAwayCheckInterval := 250      ; How often to check mouse when far away
    static farAwayTimer := 0                ; Timer for less frequent updates
    static instantTriggerSize := 5          ; Will be recalculated based on screen size
    static triggerDelay := 250              ; Trigger delay in ms
    static glowColor := 0                   ; System accent color
    static detectionRange := 50            ; Will be recalculated based on screen size
    
    ; Percentage-based sizing (added for resolution independence)
    static cornerSizePercentage := 0.01     ; 1% of screen size
    static glowRadiusPercentage := 0.04     ; 4% of screen size
    static instantTriggerSizePercentage := 0.005 ; 0.5% of screen size
    static detectionRangePercentage := 0.12 ; 12% of screen size
    
    ; Initialize everything
    static __New() {
        ; Get screen dimensions and calculate sizes relative to screen
        screenWidth := A_ScreenWidth
        screenHeight := A_ScreenHeight
        smallerDimension := Min(screenWidth, screenHeight)
        
        ; Calculate all sizes based on screen dimensions
        this.cornerSize := Max(Round(this.cornerSizePercentage * smallerDimension), 15)
        this.glowRadius := Round(this.glowRadiusPercentage * smallerDimension)
        this.instantTriggerSize := Max(Round(this.instantTriggerSizePercentage * smallerDimension), 5)
        this.detectionRange := Round(this.detectionRangePercentage * smallerDimension)
        
        ; Get system theme color
        this.GetSystemAccentColor()
        
        ; Create glow layers
        this.CreateGlowLayers()
        
        ; Pre-calculate layer opacities
        this.PreCalculateLayerProperties()
        
        ; Store timer function references
        this.timerFunc := this.DeferredUpdate.Bind(this)
        this.farAwayTimerFunc := this.FarAwayCheck.Bind(this)
        
        ; Add hotkey to toggle functionality (Ctrl+Alt+C)
        Hotkey "^!c", this.ToggleHotCorner.Bind(this)
        
        ; Set up low-level mouse hook
        this.mouseHook := DllCall("SetWindowsHookEx", 
            "int", 14, 
            "ptr", CallbackCreate((nCode, wParam, lParam) => this.LowLevelMouseProc(nCode, wParam, lParam)), 
            "ptr", 0, 
            "uint", 0)
        
        ; Start the background checking timer
        this.farAwayTimer := SetTimer(this.farAwayTimerFunc, this.farAwayCheckInterval)
        
        ; Cleanup on exit
        OnExit(*) => (DllCall("UnhookWindowsHookEx", "ptr", this.mouseHook), 
                     this.HideAllLayers(),
                     SetTimer(this.farAwayTimer, 0))
    }
    
        ; Get system accent color
    static GetSystemAccentColor() {
        ; Default color if registry read fails
        this.glowColor := 0x2233AA
    
        ; Try DWM AccentColor first
        try {
            dwmValue := RegRead("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\DWM", "AccentColor")
        
            if (dwmValue != "") {
                ; Convert from AABBGGRR to RRGGBB
                a := (dwmValue >> 24) & 0xFF
                r := dwmValue & 0xFF
                g := (dwmValue >> 8) & 0xFF
                b := (dwmValue >> 16) & 0xFF
            
                this.glowColor := (r << 16) | (g << 8) | b
            }
        } catch {
            ; Fall back to ColorizationColor
            try {
                colorValue := RegRead("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\DWM", "ColorizationColor")
            
                if (colorValue != "") {
                    ; ARGB format
                    a := (colorValue >> 24) & 0xFF
                    r := (colorValue >> 16) & 0xFF
                    g := (colorValue >> 8) & 0xFF
                    b := colorValue & 0xFF
                
                   this.glowColor := (r << 16) | (g << 8) | b
                }
            } catch {
                ; Try Explorer Accent as last resort
                try {
                    accentValue := RegRead("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent", "AccentColorMenu")
                
                    if (accentValue != "") {
                        ; Convert BGR to RGB
                        r := accentValue & 0xFF
                        g := (accentValue >> 8) & 0xFF
                        b := (accentValue >> 16) & 0xFF
                    
                        this.glowColor := (r << 16) | (g << 8) | b
                    }
                } catch {
                    ; Keep default blue
                }
            }
        }
    }

    ; Pre-calculate layer properties for smooth gradient
    static PreCalculateLayerProperties() {
        numLayers := this.glowLayers.Length
        
        for i, layer in this.glowLayers {
            layerNum := numLayers - i + 1
            layerRatio := layerNum / numLayers
            
            ; Cubic curve for smooth gradient
            layer.layerFactor := layerRatio * layerRatio * layerRatio
            
            ; Progressive opacity based on layer position
            if (layerNum == 1)
                layer.maxOpacity := 1
            else if (layerNum == 2)
                layer.maxOpacity := 2
            else if (layerNum <= 5)
                layer.maxOpacity := layerNum
            else if (layerNum <= 10)
                layer.maxOpacity := layerNum * 0.6
            else
                layer.maxOpacity := 255
        }
    }
    
    ; Create glow layers
    static CreateGlowLayers() {
        ; 12 layers for smooth gradient
        numLayers := 12
        
        Loop numLayers {
            ; Create GUI for each layer
            layer := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
            layer.BackColor := Format("0x{:06X}", this.glowColor)
            layer.Opt("+LastFound")
            hwnd := WinExist()
            
            ; Linear radius progression
            layerRadius := this.glowRadius * (A_Index / numLayers)
            
            ; Create quarter-circle region
            this.CreateQuarterCircleRegion(hwnd, layerRadius)
            
            ; Start hidden
            layer.Hide()
            
            ; Store layer info
            this.glowLayers.Push({ 
                gui: layer, 
                hwnd: hwnd,
                radius: layerRadius,
                visible: false,
                lastOpacity: 0
            })
        }
    }
    
    ; Track notification timing
    static LastNotificationTime(newValue := "") {
        static timeValue := 0
        
        if (newValue != "") {
            timeValue := newValue
        }
        
        return timeValue
    }
    
    ; Create quarter-circle shape for corner
    static CreateQuarterCircleRegion(hwnd, radius) {
        intRadius := Integer(radius)
        
        hQuarterRect := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", intRadius, "int", intRadius)
        hCircle := DllCall("CreateEllipticRgn", "int", 0, "int", 0, "int", intRadius*2, "int", intRadius*2)
        
        ; Combine shapes with AND operation
        DllCall("CombineRgn", "ptr", hQuarterRect, "ptr", hQuarterRect, "ptr", hCircle, "int", 4)
        
        ; Apply and clean up
        DllCall("SetWindowRgn", "ptr", hwnd, "ptr", hQuarterRect, "int", true)
        DllCall("DeleteObject", "ptr", hCircle)
    }
    
    ; Hide all layers
    static HideAllLayers() {
        if (!this.isVisible)
            return
            
        for _, layer in this.glowLayers {
            if (layer.visible) {
                layer.gui.Hide()
                layer.visible := false
                layer.lastOpacity := 0
            }
        }
        this.isVisible := false
    }
    
    ; Check if mouse is far from corner
    static FarAwayCheck() {
        if (this.timerActive)
            return
            
        CoordMode "Mouse", "Screen"
        MouseGetPos &xpos, &ypos
        
        ; Close range check
        inRange := (xpos <= this.glowRadius * 2 && ypos <= this.glowRadius * 2)
        
        ; Far away check
        completelyOutOfRange := (xpos > this.detectionRange || ypos > this.detectionRange)
        
        if (inRange && this.mouseOutOfRange) {
            ; Mouse just entered range
            this.mouseOutOfRange := false
            this.timerActive := true
            SetTimer(this.timerFunc, this.updateInterval)
        } else if (completelyOutOfRange) {
            ; Mouse completely left range
            this.mouseOutOfRange := true
            
            if (this.timerActive) {
                this.timerActive := false
                SetTimer(this.timerFunc, 0)
            }
            
            if (this.isVisible) {
                this.HideAllLayers()
            }
        }
    }
    
    ; Throttle updates for performance
    static ShouldUpdate(x, y) {
        if (Abs(x - this.lastX) < this.updateThreshold && Abs(y - this.lastY) < this.updateThreshold)
            return false
            
        currentTick := A_TickCount
        if (currentTick - this.lastTickCount < this.minUpdateInterval)
            return false
            
        this.lastX := x
        this.lastY := y
        this.lastTickCount := currentTick
        return true
    }
    
    ; Update glow visuals
    static UpdateGlow(x, y) {
        ; Quick exit if out of range
        if (x > this.glowRadius * 2 || y > this.glowRadius * 2) {
            if (this.isVisible) {
                this.HideAllLayers()
            }
            return
        }
        
        ; Check if update needed
        if (!this.ShouldUpdate(x, y))
            return
        
        ; Calculate distance from corner
        squareDistance := x*x + y*y
        maxSquareDistance := this.glowRadius * this.glowRadius
        
        if (squareDistance <= maxSquareDistance) {
            distance := Sqrt(squareDistance)
            distanceRatio := distance / this.glowRadius
            
            ; Quadratic falloff
            baseOpacity := 255 * (1 - distanceRatio * distanceRatio)
            
            anyVisible := false
            
            for i, layer in this.glowLayers {
                ; Calculate layer opacity
                if (layer.maxOpacity < 255) {
                    opacity := Integer(Min(baseOpacity * layer.layerFactor, layer.maxOpacity))
                } else {
                    opacity := Integer(baseOpacity * layer.layerFactor)
                }
                
                opacity := Max(1, Min(255, opacity))
                
                if (opacity > 1) {
                    if (Abs(opacity - layer.lastOpacity) > 3 || !layer.visible) {
                        if (!layer.visible) {
                            layer.gui.Show("x0 y0 w" layer.radius*2 " h" layer.radius*2 " NoActivate")
                            layer.visible := true
                        }
                        
                        WinSetTransparent(opacity, layer.hwnd)
                        layer.lastOpacity := opacity
                    }
                    
                    anyVisible := true
                } else if (layer.visible) {
                    layer.gui.Hide()
                    layer.visible := false
                    layer.lastOpacity := 0
                }
            }
            
            this.isVisible := anyVisible
        } else if (this.isVisible) {
            this.HideAllLayers()
        }
    }
    
    ; Main update function
    static DeferredUpdate() {
        if (!this.enabled) {
            return
        }
        
        CoordMode "Mouse", "Screen"
        MouseGetPos &xpos, &ypos
        
        if (xpos > this.detectionRange || ypos > this.detectionRange) {
            if (this.isVisible) {
                this.HideAllLayers()
            }
            
            if (!this.mouseOutOfRange) {
                this.mouseOutOfRange := true
                this.timerActive := false
                SetTimer(this.timerFunc, 0)
            }
            
            return
        }
        
        if (xpos <= this.glowRadius * 2 && ypos <= this.glowRadius * 2) {
            this.UpdateGlow(xpos, ypos)
        } else if (this.isVisible) {
            this.HideAllLayers()
        }
        
        ; Instant corner trigger
        currentTime := A_TickCount
        if (!this.triggered && xpos <= this.instantTriggerSize && ypos <= this.instantTriggerSize 
            && (currentTime - this.lastTriggerTime > this.triggerCooldown)) {
            this.SendTaskView()
            this.lastTriggerTime := currentTime
            this.triggered := true
        } else if (xpos > this.instantTriggerSize || ypos > this.instantTriggerSize) {
            if (this.triggered) {
                this.triggered := false
            }
        }
    }
    
    ; Send Task View keyboard shortcut
    static SendTaskView() {
        static KEYEVENTF_KEYDOWN := 0
        static KEYEVENTF_KEYUP := 2
        static VK_LWIN := 0x5B
        static VK_TAB := 0x09
        
        ; Press Win+Tab
        DllCall("keybd_event", "UChar", VK_LWIN, "UChar", 0, "UInt", KEYEVENTF_KEYDOWN, "Ptr", 0)
        Sleep 15
        DllCall("keybd_event", "UChar", VK_TAB, "UChar", 0, "UInt", KEYEVENTF_KEYDOWN, "Ptr", 0)
        Sleep 15
        DllCall("keybd_event", "UChar", VK_TAB, "UChar", 0, "UInt", KEYEVENTF_KEYUP, "Ptr", 0)
        Sleep 15
        DllCall("keybd_event", "UChar", VK_LWIN, "UChar", 0, "UInt", KEYEVENTF_KEYUP, "Ptr", 0)
    }
    
    ; Toggle Hot Corner on/off
    static ToggleHotCorner(*) {
        this.enabled := !this.enabled

        if (!this.enabled && this.isVisible) {
            this.HideAllLayers()
        }

        currentTime := A_TickCount
        if (currentTime - this.LastNotificationTime() < 5000) {
            TrayTip  
        }

        TrayTip "Hot Corner", (this.enabled ? "Enabled" : "Disabled"), "Mute"
        this.LastNotificationTime(currentTime)
    }
    
    ; Low-level mouse hook
    static LowLevelMouseProc(nCode, wParam, lParam) {
        static WM_MOUSEMOVE := 0x0200
        
        if (nCode >= 0 && wParam = WM_MOUSEMOVE) {
            if (!this.timerActive && this.enabled) {
                CoordMode "Mouse", "Screen"
                MouseGetPos &xpos, &ypos
                
                if (xpos <= this.glowRadius * 2 && ypos <= this.glowRadius * 2) {
                    this.mouseOutOfRange := false
                    this.timerActive := true
                    SetTimer(this.timerFunc, this.updateInterval)
                    
                    if (xpos <= this.instantTriggerSize && ypos <= this.instantTriggerSize) {
                        currentTime := A_TickCount
                        if (!this.triggered && (currentTime - this.lastTriggerTime > this.triggerCooldown)) {
                            this.SendTaskView()
                            this.lastTriggerTime := currentTime
                            this.triggered := true
                        }
                    }
                }
            }
        }
        
        return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
    }
}

; Start the hot corner script
HotCorner.__New()
