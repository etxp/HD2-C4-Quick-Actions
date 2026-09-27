"""Remove Lua comments from a delivery copy; keep strings and line numbers."""
import re

def strip_comments(source):
    result = []
    index = 0

    def long_end(start):
        match = re.match(r'\[(=*)\[', source[start:])
        if not match:
            return None
        closing = ']' + match[1] + ']'
        end = source.find(closing, start + len(match[0]))
        if end < 0:
            raise ValueError('Unclosed Lua long bracket')
        return end + len(closing)

    while index < len(source):
        if source.startswith('--', index):
            end = long_end(index + 2)
            if end is None:
                end = source.find('\n', index)
                if end < 0:
                    end = len(source)
            comment = source[index:end]
            result.append(' ' + '\n' * comment.count('\n'))
            index = end
        elif source[index] in ('"', "'"):
            start, quote = index, source[index]
            index += 1
            while index < len(source):
                if source[index] == '\\':
                    index += 2
                elif source[index] == quote:
                    index += 1
                    break
                else:
                    index += 1
            else:
                raise ValueError('Unclosed Lua quoted string')
            result.append(source[start:index])
        elif source[index] == '[' and (end := long_end(index)) is not None:
            result.append(source[index:end])
            index = end
        else:
            result.append(source[index])
            index += 1
    return ''.join(result)
