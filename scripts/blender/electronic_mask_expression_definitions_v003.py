"""Frozen pixel-art definitions shared by authoring, registration and catalog export."""
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
        stamp(['11111']*14,8,4); stamp(['11111']*14,24,4)
    elif key=='happy':
        pair(['001110000','011111000','110001100','110001100'],6,6)
        stamp(['11000000011','01100000110','00111111100','00011111000'],13,15)
    elif key=='sad':
        pair(['111111100','011111110','000000011'],6,6)
        stamp(['11']*5,8,10); stamp(['11']*5,27,10)
        stamp(['00011111000','00111111100','01100000110'],13,17)
    elif key=='angry':
        pair(['111000000','111110000','001111100','000011110','000000111','000000111'],6,4)
        pair(['000011111','000011111'],6,11)
        stamp(['1111111','1111111'],15,17)
    elif key=='surprised':
        pair(['01111000','11001100','11001100','11001100','11001100','11001100','01111000'],7,4)
        stamp(['01110','11011','11011','11011','11011','01110'],16,14)
    elif key=='love':
        pair(['011001100','111111110','111111110','011111100','001111000','000110000'],6,6)
        stamp(['11000000011','01100000110','00111111100'],13,15)
    elif key=='question':
        lines=['01110','11011','00011','00110','01100','00000','01100']
        # Two-by-two blocks form a thick, unmistakable question mark.
        for row,line in enumerate(lines):
            for col,c in enumerate(line):
                if c=='1': stamp(['11','11'],13+col*2,3+row*2)
    elif key=='alert':
        stamp(['1111']*11,16,2); stamp(['1111']*3,16,17)
    else: raise ValueError(key)
    assert result and all(0<=x<37 and 0<=y<22 for x,y in result)
    return sorted(result,key=lambda p:(p[1],p[0]))
