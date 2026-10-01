"""v004 mouth-free, fuller pixel-art plan shared by authoring and registration."""
PIXEL_CELL_SIZE_M = .0118
PIXEL_PITCH_M = .014
EXPRESSIONS = [
    ('neutral','平静','emotion','#21bfff',(0.001,.10,1),True),
    ('happy','开心','emotion','#29e9ff',(.001,.65,1),True),
    ('sad','难过','emotion','#777bff',(.15,.16,1),True),
    ('angry','生气','emotion','#ff3028',(1,.012,.003),True),
    ('surprised','惊讶','emotion','#ffe45c',(1,.72,.025),True),
    ('love','爱心','emotion','#ff6abb',(1,.06,.4),True),
    ('question','疑问','symbol','#ffd24a',(1,.55,.012),False),
    ('alert','警示','symbol','#a1fff2',(.15,1,.78),False),
]
def asset_id(key): return 'CHR-PLY-BUNNY01-EXPR-'+key.upper()
def slug(key): return 'chr_bunny01_expression_'+key
def pixels(key):
    result=set()
    def stamp(lines,x,y):
        for row,line in enumerate(lines):
            for col,c in enumerate(line):
                if c=='1': result.add((x+col,y+row))
    def pair(lines,x=6,y=6):
        stamp(lines,x,y); stamp([line[::-1] for line in lines],37-x-len(lines[0]),y)
    if key=='neutral':
        stamp(['111111']*15,7,3); stamp(['111111']*15,24,3)
    elif key=='happy':
        pair(['00011111000','00111111100','01111111110','11111111111',
              '11110001111','11100000111','11100000111','11100000111'],5,5)
    elif key=='sad':
        pair(['11111111000','11111111100','00111111110','00000011111','00000000111'],5,5)
        stamp(['111']*6,8,10); stamp(['111']*6,26,10)
    elif key=='angry':
        pair(['11110000000','11111100000','01111111000','00011111110',
              '00000111111','00000001111','00000001111'],5,4)
        pair(['00000111111']*3,5,11)
    elif key=='surprised':
        pair(['001111100','011111110','111000111','111000111','111000111',
              '111000111','111000111','111000111','111000111','111000111',
              '011111110','001111100'],6,4)
    elif key=='love':
        pair(['01110001110','11111011111','11111111111','11111111111',
              '11111111111','01111111110','00111111100','00011111000',
              '00001110000','00000100000'],5,5)
    elif key=='question':
        lines=['0111110','1111111','1100011','0001111','0011110','0011000','0000000','0011000']
        # Two-by-two blocks form a thick, unmistakable question mark.
        for row,line in enumerate(lines):
            for col,c in enumerate(line):
                if c=='1': stamp(['11','11'],11+col*2,2+row*2)
    elif key=='alert':
        stamp(['111111']*12,15,2); stamp(['111111']*4,15,17)
    else: raise ValueError(key)
    assert result and all(0<=x<37 and 0<=y<22 for x,y in result)
    if key not in ['question','alert']:
        assert all(x<=15 or x>=21 for x,y in result), 'No central mouth cells'
    return sorted(result,key=lambda p:(p[1],p[0]))
