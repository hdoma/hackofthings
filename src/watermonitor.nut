
/* Uses electric IMP reference->hardware->lineUART device and one-wire example code
*/ 


// =============================================================================
class LineUART {
    
    _pins = null;
    _buf = null;
    _callback = null;
    _eol_chars = null;
    
    // -------------------------------------------------------------------------
    // Constructor require the hardware.uartXX pins that will be used for communication.
    constructor(pins) {
        _pins = pins;

        setbuffersize();
        seteol();
    }
    
    // -------------------------------------------------------------------------
    // This function accepts the usual uart.configure() parameters. The callback 
    // function must accept a buffer (blob) as a parameter which will contain the 
    // uart data read. 
    function configure(speed, word_size, parity, stop, flags, callback = null) {
        
        _pins.configure(speed, word_size, parity, stop, flags, _read.bindenv(this));
        setcallback(callback)
        
        return this;
    }    

    // -------------------------------------------------------------------------
    // Request a specific buffer size. Clears the current buffer. Default is 100 bytes.
    function setbuffersize(buf_size = 100) {
        _buf = blob(buf_size);
        return this;
    }
    

    // -------------------------------------------------------------------------
    // Request specific EOL characters to detect. Default is a carriage return. 
    // Accepts a character (integer), a string or an array of characters.
    function seteol(eol_chars = '\n') {
        _eol_chars = [];
        if (typeof eol_chars == "integer") {
            _eol_chars.push(eol_chars);
        } else if (typeof eol_chars == "string" || typeof eol_chars == "array") {
            foreach (ch in eol_chars) {
                if (typeof ch == "integer") {
                    _eol_chars.push(ch);
                }
            }
        }
        return this;
    }

    
    // -------------------------------------------------------------------------
    // Assigns a new callback function to handle incoming data
    function setcallback(callback = null) {
        _callback = callback;
        return this;
    }
    
    
    // -------------------------------------------------------------------------
    // Writes the provided buffer (string or blob) to the UART. Optionally,
    // an callback can be provided for returning (only) the next response.
    function write(buf, callback = null) {
        _pins.write(buf);
        
        if (callback) {
            local old_callback = _callback;
            local new_callback = callback;
            _callback = function(buf) {
                _callback = old_callback;
                new_callback(buf);
            }.bindenv(this);
        }
        
        return this;
    }
    
    // -------------------------------------------------------------------------
    // Flushes the output buffer to the UART
    function flush() {
        _pins.flush();
        return this;
    }
    
    // -------------------------------------------------------------------------
    // Disables the UART to conserve power
    function disable() {
        _pins.disable();
        return this;
    }
    
    
    // ================[ Private functions ]================
    
    
    // -------------------------------------------------------------------------
    // When the buffer is full or a EOL character is detected, this cleans up and
    // delivers the resulting buffer.
    function _ready(force_return = false) {
        local len = _buf.tell();
        _buf.seek(0);
        local buf = _buf.readblob(len);
        _buf.seek(0);
        if (_callback && !force_return) {
            if (len > 0) _callback(buf);
        } else {
            return buf;
        }
    }
    
    // -------------------------------------------------------------------------
    // Handles the UART events to drain the input buffer into the local buffer.
    function _read() {
        
        // If the callback function has been removed then don't read the UART.
        if (!_callback) return;
        
        local ch = null;
        do {
            ch = _pins.read();
            if (ch == -1) break;
            if (_eol_chars.find(ch) != null) {
                _ready();
                break;
            }
            _buf.writen(ch, 'b');
        } while (_buf.tell() < _buf.len());
        
        if (_buf.tell() == _buf.len()) {
            _ready();
        }
    }
}


// =============================================================================
class owPIN {
    
    _ow = null;
    _pins = null;
    _buf = null;
    _callback = null;
    _eol_chars = null;
    
    // -------------------------------------------------------------------------
    // Constructor require the hardware.uartXX pins that will be used for communication.
    constructor(pins) {
        _ow = pins;

    }


	function one_wire_reset()
	{
	    // Configure UART for 1-Wire RESET timing
	    
	    _ow.configure(9600, 8, PARITY_NONE, 1, NO_CTSRTS)
	    _ow.write(0xF0)
	    _ow.flush()
	    if (_ow.read() == 0xF0)
	    {
	        // UART RX will read TX if there's no device connected
	        
	        server.log("No 1-Wire devices are present.")
	        return false
	    } 
	    else 
	    {
	        // Switch UART to 1-Wire data speed timing
	        
	        _ow.configure(115200, 8, PARITY_NONE, 1, NO_CTSRTS)
	        return true
	    }
	}
	 
	function one_wire_write_byte(byte)
	{
	    for (local i = 0 ; i < 8 ; i++, byte = byte >> 1)
	    {
	        // Run through the bits in the byte, extracting the
	        // LSB (bit 0) and sending it to the bus
	        
	        one_wire_bit(byte & 0x01)
	    }
	} 
	 
	 
	function one_wire_read_byte()
	{
	    local byte = 0
	    for (local i = 0 ; i < 8 ; i++)
	    {
	        // Build up byte bit by bit, LSB first
	        
	        byte = (byte >> 1) + 0x80 * one_wire_bit(1)
	    }
	    
	    return byte
	}
	 
	 
	function one_wire_bit(bit)
	{
	    bit = bit ? 0xFF : 0x00
	    _ow.write(bit)
	    _ow.flush()
	    local return_value = _ow.read() == 0xFF ? 1 : 0
	    return return_value
	}
	 
	 
	// Wake up every 5 seconds and write to the server
	 
	function awake_and_get_temp()
	{
	    local temp_LSB = 0
	    local temp_MSB = 0
	    local temp_celsius = 0
	    
	    if (one_wire_reset())
	    {
	        one_wire_write_byte(0xCC)
	        one_wire_write_byte(0x44)
	        
	        imp.sleep(0.8)    // Wait for at least 750ms for data to be collated
	    
	        one_wire_reset()
	        one_wire_write_byte(0xCC)
	        one_wire_write_byte(0xBE)
	        
	        temp_LSB = one_wire_read_byte()
	        temp_MSB = one_wire_read_byte()
	    
	        one_wire_reset()   // Reset bus to stop sensor sending unwanted data
	    
	        temp_celsius = ((temp_MSB * 256) + temp_LSB) / 16.0
	        
	        server.log(format("Temperature: %3.2f degrees C", temp_celsius))
	        
	        return temp_celsius;
	    }
	    else {
	        server.log(format("error resetting sensor"));
	    }
	}
 
}



// CODE ============================

local now = date();

uartDO <- LineUART(hardware.uart57);
uartDO.configure(38400, 8, PARITY_NONE, 1, NO_CTSRTS)
.setbuffersize(80)  // Fire an event when there are eighty bytes in the buffer
.seteol("\r");    // or when a carriage return or newline is received.8


uartPH <- LineUART(hardware.uart12);
uartPH.configure(38400, 8, PARITY_NONE, 1, NO_CTSRTS)
.setbuffersize(80)  // Fire an event when there are eighty bytes in the buffer
.seteol("\r");    // or when a carriage return or newline is received.8


// define one wire sensor for pins 8 and 9
tempOW <- owPIN(hardware.uart1289) 


function poll() {
    
    local valueDO = 0;
    local valuePH = 0;

    // read temperature sensor
    valueTEMP <- tempOW.awake_and_get_temp()
    
    //server.log(format("Temperature: %3.2f degrees C", valueTEMP))

    //server.log("sending request for ID to DO")
    uartDO.write("R\r\n", function(bufDO) {
        valueDO = bufDO.tostring().tofloat();
       
        uartPH.write("R\r\n", function(bufPH) {
            valuePH = bufPH.tostring().tofloat();
           
            // Create data stream
            now = date();
            
            server.log(format( "new data timestampt: %d",now.time));
            agent.send("data",{"TS": now.time, "TEMP": valueTEMP, "DO": valueDO, "PH" : valuePH })
            
            imp.wakeup(20, poll);
        })
    
    })
}

poll();





