package dev.krane.anicli;

public class Continue extends Launch {
    @Override
    String[] args() {
        return new String[] {"--dub", "--continue"};
    }
}
